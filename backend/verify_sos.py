"""Exercise private SOS creation and operator delivery without retaining test data."""
from uuid import uuid4
from datetime import datetime, timezone
from psycopg import errors, sql
from app.db import ROOT, connect


def main():
    with connect(admin=True) as conn:
        try:
            if not conn.execute("SELECT to_regclass('trujillo.sos_migrations')").fetchone()[0]:
                conn.execute((ROOT / 'migrations/014_sos.sql').read_text(encoding='utf-8'))
            admin = conn.execute('SELECT current_user').fetchone()[0]
            conn.execute(sql.SQL('GRANT trujillo_api TO {}').format(sql.Identifier(admin)))
            prefix = 'sos-check-' + str(uuid4())
            users = []
            for index, role in enumerate(('citizen', 'operator')):
                users.append(conn.execute(
                    "INSERT INTO trujillo.users(auth_provider,auth_subject,display_name,role) VALUES('firebase',%s,'Prueba SOS',%s) RETURNING id",
                    (prefix + str(index), role)).fetchone()[0])

            def as_user(index):
                conn.execute('RESET ROLE')
                conn.execute("SELECT set_config('app.firebase_uid',%s,true)", (prefix + str(index),))
                conn.execute('SET LOCAL ROLE trujillo_api')

            as_user(1)
            device = uuid4()
            conn.execute('SELECT trujillo.push_register(%s,%s,%s,%s,%s,%s,%s)',
                         (device, prefix + '-operator-token', False, True, None, None, 500))
            as_user(0)
            request = uuid4()
            args = (request, -8.11, -79.03)
            first = conn.execute('SELECT trujillo.submit_sos(%s,%s,%s)', args).fetchone()[0]
            again = conn.execute('SELECT trujillo.submit_sos(%s,%s,%s)', args).fetchone()[0]
            assert first['id'] == again['id'] and first['source'] == 'sos'
            try:
                with conn.transaction():
                    conn.execute('SELECT trujillo.submit_sos(%s,%s,%s)', (request, -8.12, -79.03))
            except errors.RaiseException:
                pass
            else:
                raise AssertionError('Reused SOS ID accepted with changed location')
            conn.execute('RESET ROLE')
            assert conn.execute('SELECT count(*) FROM trujillo.reports WHERE user_id=%s', (users[0],)).fetchone()[0] == 0
            assert conn.execute('SELECT count(*) FROM trujillo.push_outbox WHERE device_id=%s', (device,)).fetchone()[0] == 1
            as_user(1)
            job = conn.execute('SELECT trujillo.push_claim()').fetchone()[0]
            assert job['target_id'] == first['id'] and job['incident'] == 'false' and job['title'].startswith('SOS')
            assert conn.execute("SELECT trujillo.push_target('operator_help',%s)", (first['id'],)).fetchone()[0]['source'] == 'sos'
            as_user(0)
            report_request = uuid4()
            report = conn.execute('SELECT trujillo.submit_report(%s,%s,%s,%s,%s,%s,%s)',
                         (report_request, 'Robo', 'Lugar de prueba', '', -8.11, -79.03, datetime.now(timezone.utc))).fetchone()[0]
            conn.execute('SET CONSTRAINTS ALL IMMEDIATE')
            conn.execute('RESET ROLE')
            assert conn.execute('SELECT count(*) FROM trujillo.help_requests WHERE user_id=%s AND request_id=%s',
                                (users[0], report_request)).fetchone()[0] == 0
            assert conn.execute('SELECT count(*) FROM trujillo.push_outbox WHERE device_id=%s AND target_id=%s',
                                (device, report['id'])).fetchone()[0] == 1
            as_user(0)
            try:
                with conn.transaction():
                    conn.execute("SELECT trujillo.push_target('operator_help',%s)", (first['id'],))
            except errors.InsufficientPrivilege:
                pass
            else:
                raise AssertionError('Citizen accessed operator SOS target')
            print('SOS: private request, retry, operator notification and permissions verified. Data rolled back.')
        finally:
            conn.rollback()


if __name__ == '__main__':
    main()
