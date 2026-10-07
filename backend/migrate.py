"""Apply the initial schema atomically and provision a restricted health role."""
import secrets
from psycopg import sql
from dotenv import dotenv_values, set_key
from app.db import ROOT, connect


def main():
    runtime = ROOT / '.env.runtime'
    with connect(admin=True) as conn:
        conn.execute('SELECT pg_advisory_xact_lock(360001)')
        exists = conn.execute("SELECT to_regclass('trujillo.schema_migrations')").fetchone()[0]
        if not exists:
            conn.execute((ROOT / 'migrations/001_initial.sql').read_text(encoding='utf-8'))
        elif conn.execute('SELECT max(version) FROM trujillo.schema_migrations').fetchone()[0] not in (1, 2, 3, 4, 5, 6):
            raise RuntimeError('Versión inesperada; no se modificó el esquema')
        role = 'trujillo_api'
        role_exists = conn.execute('SELECT 1 FROM pg_roles WHERE rolname=%s', (role,)).fetchone()
        if not role_exists:
            password = secrets.token_urlsafe(32)
            conn.execute(sql.SQL('CREATE ROLE {} LOGIN PASSWORD {} NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS').format(sql.Identifier(role), sql.Literal(password)))
            env = dotenv_values(ROOT / '.env')
            env['PGUSER'] = role + '.' + env['PGUSER'].split('.', 1)[1] if '.' in env['PGUSER'] else role
            env['PGPASSWORD'] = password
            for key, value in env.items():
                if key.startswith('PG') and value is not None:
                    set_key(str(runtime), key, value)
        elif not runtime.exists():
            raise RuntimeError('El rol ya existe pero falta .env.runtime; no se rotó su contraseña')
        conn.execute('GRANT USAGE ON SCHEMA trujillo TO trujillo_api')
        conn.execute('GRANT SELECT ON trujillo.schema_migrations TO trujillo_api')
        conn.execute('DROP POLICY IF EXISTS runtime_version ON trujillo.schema_migrations')
        conn.execute('CREATE POLICY runtime_version ON trujillo.schema_migrations FOR SELECT TO trujillo_api USING (true)')
        if conn.execute('SELECT max(version) FROM trujillo.schema_migrations').fetchone()[0] == 1:
            conn.execute((ROOT / 'migrations/002_identity.sql').read_text(encoding='utf-8'))
        if conn.execute('SELECT max(version) FROM trujillo.schema_migrations').fetchone()[0] == 2:
            conn.execute((ROOT / 'migrations/003_reports.sql').read_text(encoding='utf-8'))
        if conn.execute('SELECT max(version) FROM trujillo.schema_migrations').fetchone()[0] == 3:
            conn.execute((ROOT / 'migrations/004_report_photos.sql').read_text(encoding='utf-8'))
        if conn.execute('SELECT max(version) FROM trujillo.schema_migrations').fetchone()[0] == 4:
            conn.execute((ROOT / 'migrations/005_corroboration.sql').read_text(encoding='utf-8'))
        if conn.execute('SELECT max(version) FROM trujillo.schema_migrations').fetchone()[0] == 5:
            conn.execute((ROOT / 'migrations/006_nearby_incidents.sql').read_text(encoding='utf-8'))
    print('Migración 6 lista. Consulta de incidentes cercanos habilitada.')


if __name__ == '__main__':
    main()
