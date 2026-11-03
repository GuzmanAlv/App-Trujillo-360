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
        elif conn.execute('SELECT max(version) FROM trujillo.schema_migrations').fetchone()[0] not in (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11):
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
        if conn.execute('SELECT max(version) FROM trujillo.schema_migrations').fetchone()[0] == 6:
            conn.execute((ROOT / 'migrations/007_nearby_identity_fix.sql').read_text(encoding='utf-8'))
        if conn.execute('SELECT max(version) FROM trujillo.schema_migrations').fetchone()[0] == 7:
            conn.execute((ROOT / 'migrations/008_report_read_permissions.sql').read_text(encoding='utf-8'))
        if conn.execute('SELECT max(version) FROM trujillo.schema_migrations').fetchone()[0] == 8:
            conn.execute((ROOT / 'migrations/009_map_viewport.sql').read_text(encoding='utf-8'))
        if conn.execute('SELECT max(version) FROM trujillo.schema_migrations').fetchone()[0] == 9:
            conn.execute((ROOT / 'migrations/010_community_groups.sql').read_text(encoding='utf-8'))
        if conn.execute('SELECT max(version) FROM trujillo.schema_migrations').fetchone()[0] == 10:
            conn.execute((ROOT / 'migrations/011_community_photos.sql').read_text(encoding='utf-8'))
        result_type = conn.execute("SELECT pg_get_function_result('trujillo.incident_reports(uuid)'::regprocedure)").fetchone()[0]
        if 'place text' not in result_type:
            conn.execute((ROOT / 'migrations/011_report_places_patch.sql').read_text(encoding='utf-8'))
        if not conn.execute("SELECT to_regclass('trujillo.workflow_migrations')").fetchone()[0]:
            conn.execute((ROOT / 'migrations/012_workflows.sql').read_text(encoding='utf-8'))
        conn.execute('GRANT SELECT ON trujillo.workflow_migrations TO trujillo_api')
        conn.execute('DROP POLICY IF EXISTS workflow_version_read ON trujillo.workflow_migrations')
        conn.execute('CREATE POLICY workflow_version_read ON trujillo.workflow_migrations FOR SELECT TO trujillo_api USING(true)')
        if not conn.execute("SELECT to_regclass('trujillo.push_migrations')").fetchone()[0]:
            conn.execute((ROOT / 'migrations/013_push.sql').read_text(encoding='utf-8'))
        # Refresh compatible public readers using the shared publication rule.
        for filename in ('007_nearby_identity_fix.sql','010_community_groups.sql','011_report_places_patch.sql'):
            source = (ROOT / 'migrations' / filename).read_text(encoding='utf-8')
            if filename == '010_community_groups.sql':
                source = source.split('-- Shared summaries')[0]
            source = source.replace('CREATE FUNCTION trujillo.nearby_incidents', 'CREATE OR REPLACE FUNCTION trujillo.nearby_incidents')
            source = source.replace("i.status IN ('pending','corroborated','verified')", 'trujillo.is_public_incident(i.status,i.corroboration_count,i.needs_review)')
            source = source.replace("i.status IN ('corroborated','verified') AND i.corroboration_count >= 3 AND NOT i.needs_review", 'trujillo.is_public_incident(i.status,i.corroboration_count,i.needs_review)')
            source = source.replace("i.status IN ('corroborated','verified') AND i.corroboration_count>=3\n AND NOT i.needs_review", 'trujillo.is_public_incident(i.status,i.corroboration_count,i.needs_review)')
            source = source.replace("i.occurred_at >= now()-interval '7 days'", "i.occurred_at > now()-interval '7 days' AND i.occurred_at<=now()")
            source = '\n'.join(line for line in source.splitlines() if 'INSERT INTO trujillo.schema_migrations' not in line)
            conn.execute(source)
    print('Base 11 compatible; solicitudes, operadores e historial habilitados.')


if __name__ == '__main__':
    main()
