"""Verify AI SQL, grants and transitions against PostgreSQL; always roll back."""
from uuid import uuid4
from psycopg import sql, errors
from psycopg.types.json import Jsonb
from app.db import connect, ROOT


def main():
    with connect(admin=True) as conn:
        try:
            if not conn.execute("SELECT to_regclass('trujillo.ai_migrations')").fetchone()[0]:
                conn.execute((ROOT / 'migrations/017_ai_candidates.sql').read_text(encoding='utf-8'))
            admin = conn.execute('SELECT current_user').fetchone()[0]
            conn.execute(sql.SQL('GRANT trujillo_api TO {}').format(sql.Identifier(admin)))
            prefix = 'ai-check-' + str(uuid4())
            actors = []
            for i, role in enumerate(('citizen', 'operator', 'operator')):
                actors.append(conn.execute("INSERT INTO trujillo.users(auth_provider,auth_subject,display_name,role) VALUES('firebase',%s,'AI test',%s) RETURNING id", (prefix+str(i), role)).fetchone()[0])
            conn.execute('INSERT INTO trujillo.ai_cameras(id) VALUES(%s)', (prefix,))
            conn.execute('INSERT INTO trujillo.ai_camera_access VALUES(%s,%s)', (prefix, actors[1]))

            def as_user(index):
                conn.execute('RESET ROLE')
                conn.execute("SELECT set_config('app.firebase_uid',%s,true)", (prefix+str(index),))
                conn.execute('SET LOCAL ROLE trujillo_api')

            def denied(query, params=(), error=errors.InsufficientPrivilege):
                try:
                    with conn.transaction():
                        conn.execute(query, params).fetchall()
                except error:
                    pass
                else:
                    raise AssertionError('Forbidden operation succeeded')

            data = dict(schemaVersion=1, type='aggression_candidate', id=prefix,
                        cameraId=prefix, modelVersion='test', confidence=.82,
                        latitude=-8.11, longitude=-79.02, detectedAt='2026-01-01T00:00:00Z')
            as_user(0)
            denied('SELECT * FROM trujillo.list_ai_candidates(NULL,50)')
            denied('SELECT trujillo.submit_ai_candidate(%s)', (Jsonb(data),))
            as_user(2)
            denied('SELECT trujillo.submit_ai_candidate(%s)', (Jsonb(data),))
            as_user(1)
            denied('SELECT * FROM trujillo.ai_candidates')
            first = conn.execute('SELECT trujillo.submit_ai_candidate(%s)', (Jsonb(data),)).fetchone()[0]
            assert conn.execute('SELECT trujillo.submit_ai_candidate(%s)', (Jsonb(data),)).fetchone()[0] == first
            denied('SELECT trujillo.submit_ai_candidate(%s)', (Jsonb({**data, 'confidence': .7}),), errors.RaiseException)
            second = conn.execute('SELECT trujillo.submit_ai_candidate(%s)', (Jsonb({**data, 'id': prefix+'-2'}),)).fetchone()[0]
            page = conn.execute('SELECT * FROM trujillo.list_ai_candidates(%s,1)', (second['sequence']+1,)).fetchone()[0]
            assert page['sequence'] == second['sequence']
            assert conn.execute('SELECT * FROM trujillo.list_ai_candidates(%s,1)', (second['sequence'],)).fetchone()[0]['sequence'] == first['sequence']
            as_user(2)
            denied("SELECT trujillo.review_ai_candidate(%s,'confirmed','Checked camera')", (first['sequence'],))
            assert all(r[0]['cameraId'] != prefix for r in conn.execute('SELECT * FROM trujillo.list_ai_candidates(NULL,101)'))
            as_user(1)
            reviewed = conn.execute("SELECT trujillo.review_ai_candidate(%s,'discarded','Checked camera')", (first['sequence'],)).fetchone()[0]
            assert reviewed['status'] == 'discarded' and reviewed['reviewedBy'] == str(actors[1]) and reviewed['reviewedAt']
            assert conn.execute("SELECT trujillo.review_ai_candidate(%s,'discarded','Checked camera')", (first['sequence'],)).fetchone()[0] == reviewed
            denied("SELECT trujillo.review_ai_candidate(%s,'confirmed','Checked camera')", (first['sequence'],), errors.RaiseException)
            conn.execute('RESET ROLE')
            conn.execute('UPDATE trujillo.ai_cameras SET active=false WHERE id=%s', (prefix,))
            as_user(1)
            denied('SELECT trujillo.submit_ai_candidate(%s)', (Jsonb(data),))
        finally:
            conn.rollback()
    print('AI permissions, pagination, immutable candidates and decisions verified; rolled back.')


if __name__ == '__main__':
    main()
