"""Exercise identity isolation against Supabase, rolling all sample data back."""
from uuid import uuid4
import psycopg
from app.db import connect

with connect() as conn:
    try:
        uid = 'test-' + str(uuid4())
        conn.execute("SELECT set_config('app.firebase_uid', %s, true)", (uid,))
        for _ in range(2):
            conn.execute("""INSERT INTO trujillo.users(auth_provider, auth_subject, display_name)
                VALUES ('firebase', %s, 'Prueba') ON CONFLICT (auth_provider, auth_subject) DO NOTHING""", (uid,))
        assert conn.execute('SELECT count(*) FROM trujillo.users').fetchone()[0] == 1
        with conn.transaction():
            try:
                with conn.transaction():
                    conn.execute("UPDATE trujillo.users SET role='admin'")
                raise AssertionError('Role escalation allowed')
            except psycopg.errors.InsufficientPrivilege:
                pass
        conn.execute("SELECT set_config('app.firebase_uid', %s, true)", (uid + '-other',))
        assert conn.execute('SELECT count(*) FROM trujillo.users').fetchone()[0] == 0
        try:
            with conn.transaction():
                conn.execute("INSERT INTO trujillo.users(auth_provider, auth_subject, display_name) VALUES ('firebase', %s, 'Otro')", (uid,))
            raise AssertionError('Foreign identity insert allowed')
        except psycopg.errors.InsufficientPrivilege:
            pass
        print('OK: perfil único, aislamiento de identidad y bloqueo de cambio de rol.')
    finally:
        conn.rollback()
