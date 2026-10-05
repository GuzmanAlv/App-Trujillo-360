"""Integration checks; all sample records are rolled back."""
from uuid import uuid4
import psycopg
from app.db import connect


def main():
    with connect(admin=True) as conn:
        try:
            citizen = conn.execute("INSERT INTO trujillo.users(auth_provider,auth_subject,display_name) VALUES ('firebase',%s,'Prueba temporal') RETURNING id", (str(uuid4()),)).fetchone()[0]
            incident = conn.execute("INSERT INTO trujillo.incidents(category,location,occurred_at) VALUES ('Robo',extensions.ST_SetSRID(extensions.ST_MakePoint(-79.0288,-8.1116),4326)::extensions.geography,now()) RETURNING id").fetchone()[0]
            query = "INSERT INTO trujillo.reports(user_id,incident_id,request_id,category,place,location,occurred_at) SELECT %s,id,%s,category,'Caso temporal',location,occurred_at FROM trujillo.incidents WHERE id=%s"
            conn.execute(query, (citizen,uuid4(),incident))
            try:
                with conn.transaction():
                    conn.execute(query, (citizen,uuid4(),incident))
            except psycopg.errors.UniqueViolation:
                pass
            else:
                raise AssertionError('Se permitió contar dos veces al mismo usuario')
            try:
                with conn.transaction():
                    conn.execute("INSERT INTO trujillo.reviews(incident_id,reviewer_id,decision,reason) VALUES (%s,%s,'verified','Prueba temporal')", (incident,citizen))
            except psycopg.errors.CheckViolation:
                pass
            else:
                raise AssertionError('Un ciudadano pudo revisar')
            conn.execute("UPDATE trujillo.users SET role='operator' WHERE id=%s", (citizen,))
            conn.execute("INSERT INTO trujillo.reviews(incident_id,reviewer_id,decision,reason) VALUES (%s,%s,'verified','Prueba temporal')", (incident,citizen))
            assert conn.execute('SELECT extensions.ST_DWithin(location,location,100) FROM trujillo.incidents WHERE id=%s',(incident,)).fetchone()[0]
        finally:
            conn.rollback()
    with connect() as conn:
        assert conn.execute('SELECT max(version) FROM trujillo.schema_migrations').fetchone()[0] == 3
        assert conn.execute('SELECT * FROM trujillo.users').fetchall() == []
    print('OK: PostGIS, duplicados, permisos de revisión y rol limitado. Datos de prueba revertidos.')


if __name__ == '__main__':
    main()
