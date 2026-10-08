import logging
import psycopg
from fastapi import Depends, FastAPI, HTTPException
from psycopg.rows import dict_row
from app.auth import identity
from app.db import connect
from app.reports import router as reports_router
from fastapi import Request
from fastapi.responses import JSONResponse

logger = logging.getLogger('uvicorn.error')


def readiness_failure_reason(error):
    """Allowlisted diagnostics only: never log raw database errors or credentials."""
    if isinstance(error, RuntimeError):
        return 'migracion_pendiente' if str(error) == 'Migración pendiente' else 'configuracion_incompleta'
    if isinstance(error, psycopg.errors.InsufficientPrivilege):
        return 'permisos_base_de_datos'
    if isinstance(error, psycopg.errors.UndefinedTable):
        return 'esquema_no_encontrado'
    message = str(error).lower()
    for fragments, reason in [
        (('password authentication failed',), 'credenciales_rechazadas'),
        (('tenant or user not found',), 'usuario_o_proyecto_pooler_incorrecto'),
        (('could not translate host name', 'name or service not known', 'nodename nor servname', 'name resolution'), 'host_no_resuelto'),
        (('timeout expired', 'connection timeout'), 'conexion_agoto_tiempo'),
        (('connection refused', 'network is unreachable', 'no route to host'), 'conexion_no_disponible'),
        (('ssl',), 'conexion_ssl'),
    ]:
        if any(fragment in message for fragment in fragments):
            return reason
    return 'error_base_de_datos'


app = FastAPI(title='Trujillo 360 API', version='0.1.0',
              description='Piloto: identidad Firebase y perfil en Supabase.')
app.include_router(reports_router)


@app.middleware('http')
async def limit_report_body(request: Request, call_next):
    if request.method == 'POST' and request.url.path == '/reports':
        # Three 2-MB images expand to about 8 MB when encoded in JSON.
        chunks = []
        size = 0
        async for chunk in request.stream():
            size += len(chunk)
            if size > 9 * 1024 * 1024:
                return JSONResponse({'detail': 'Fotos demasiado grandes'}, status_code=413)
            chunks.append(chunk)
        request._body = b''.join(chunks)
    return await call_next(request)


@app.get('/health')
def health():
    return {'status': 'ok'}


@app.get('/ready')
def ready():
    try:
        with connect() as conn:
            version = conn.execute(
                'SELECT max(version) FROM trujillo.schema_migrations').fetchone()[0]
            if version != 11:
                raise RuntimeError('Migración pendiente')
    except (psycopg.Error, RuntimeError) as error:
        logger.error('READY_FAIL reason=%s', readiness_failure_reason(error))
        # Do not disclose host, credentials or database diagnostics over HTTP.
        raise HTTPException(503, 'Base de datos no disponible') from None
    return {'status': 'ready', 'schema_version': version}


@app.get('/me')
def me(claims=Depends(identity)):
    name = str(claims.get('name') or 'Usuario').strip()[:100] or 'Usuario'
    try:
        with connect() as conn:
            conn.execute("SELECT set_config('app.firebase_uid', %s, true)", (claims['sub'],))
            conn.execute('''INSERT INTO trujillo.users(auth_provider, auth_subject, display_name)
                            VALUES ('firebase', %s, %s)
                            ON CONFLICT (auth_provider, auth_subject) DO NOTHING''', (claims['sub'], name))
            with conn.cursor(row_factory=dict_row) as cursor:
                cursor.execute('''SELECT id, display_name, role, status, created_at
                                  FROM trujillo.users WHERE auth_provider='firebase' AND auth_subject=%s''', (claims['sub'],))
                user = cursor.fetchone()
            if user is None:
                raise RuntimeError('Perfil no disponible')
            if user['status'] != 'active':
                raise HTTPException(403, 'Cuenta suspendida')
            return user
    except (psycopg.Error, RuntimeError):
        raise HTTPException(503, 'No se pudo consultar el perfil') from None
