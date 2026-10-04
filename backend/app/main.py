import psycopg
from fastapi import FastAPI, HTTPException
from app.db import connect

app = FastAPI(title='Trujillo 360 API', version='0.1.0',
              description='Base del piloto. Login y operaciones ciudadanas pendientes.')


@app.get('/health')
def health():
    return {'status': 'ok'}


@app.get('/ready')
def ready():
    try:
        with connect() as conn:
            version = conn.execute(
                'SELECT max(version) FROM trujillo.schema_migrations').fetchone()[0]
            if version != 1:
                raise RuntimeError('Migración pendiente')
    except (psycopg.Error, RuntimeError):
        # Do not disclose host, credentials or database diagnostics over HTTP.
        raise HTTPException(503, 'Base de datos no disponible') from None
    return {'status': 'ready', 'schema_version': version}
