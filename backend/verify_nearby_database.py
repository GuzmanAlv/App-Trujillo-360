"""Check community feed using the restricted role; all test data rolls back."""
from uuid import uuid4
from app.db import connect


def main():
    with connect() as conn:
        try:
            uid = 'nearby-test-' + str(uuid4())
            conn.execute("SELECT set_config('app.firebase_uid',%s,true)", (uid,))
            conn.execute("INSERT INTO trujillo.users(auth_provider,auth_subject,display_name) VALUES('firebase',%s,'Prueba cercanos')", (uid,))
            conn.execute('SELECT * FROM trujillo.nearby_incidents(%s,%s,%s)', (-8.11, -79.02, 3000)).fetchall()
            print('OK: consulta comunitaria con el rol restringido.')
        finally:
            conn.rollback()

if __name__ == '__main__':
    main()
