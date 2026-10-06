"""Run after migration 004. All test rows are rolled back."""
import base64
import io
from datetime import datetime, timezone
from uuid import uuid4
import psycopg
from psycopg.types.json import Jsonb
from PIL import Image
from app.db import connect
from app.photos import PhotoInput, normalize_photo


def main():
    buffer = io.BytesIO()
    Image.new('RGB', (16, 16), 'blue').save(buffer, 'PNG')
    photo = normalize_photo(PhotoInput(id=uuid4(), content_base64=base64.b64encode(buffer.getvalue()).decode()))
    with connect() as conn:
        try:
            uid = 'photo-test-' + str(uuid4())
            conn.execute("SELECT set_config('app.firebase_uid',%s,true)", (uid,))
            conn.execute("INSERT INTO trujillo.users(auth_provider,auth_subject,display_name) VALUES('firebase',%s,'Prueba fotos')", (uid,))
            args = (uuid4(), 'Robo', 'Prueba fotos', '', -8.11, -79.02, datetime.now(timezone.utc), Jsonb([photo]))
            query = 'SELECT trujillo.submit_report_with_photos(%s,%s,%s,%s,%s,%s,%s,%s)'
            first = conn.execute(query, args).fetchone()[0]
            assert first == conn.execute(query, args).fetchone()[0]
            assert first['photo_count'] == 1
            assert conn.execute('SELECT count(*) FROM trujillo.report_photos WHERE report_id=%s', (first['id'],)).fetchone()[0] == 1
            assert conn.execute('SELECT count(*) FROM trujillo.incidents WHERE id=%s', (first['incident_id'],)).fetchone()[0] == 1
            try:
                with conn.transaction():
                    conn.execute(query, (*args[:-1], Jsonb([])))
                raise AssertionError('Se aceptó cambiar fotos en el reintento')
            except psycopg.errors.RaiseException:
                pass
            # A duplicate photo ID must roll back the new report and incident.
            another_request = uuid4()
            try:
                with conn.transaction():
                    conn.execute(query, (another_request, *args[1:4], -9.0, *args[5:]))
                raise AssertionError('Se aceptó una foto perteneciente a otro reporte')
            except psycopg.errors.UniqueViolation:
                pass
            assert conn.execute('SELECT count(*) FROM trujillo.reports WHERE request_id=%s', (another_request,)).fetchone()[0] == 0
            conn.execute("SELECT set_config('app.firebase_uid',%s,true)", (uid + '-other',))
            assert conn.execute('SELECT count(*) FROM trujillo.reports WHERE id=%s', (first['id'],)).fetchone()[0] == 0
            assert conn.execute('SELECT count(*) FROM trujillo.report_photos WHERE report_id=%s', (first['id'],)).fetchone()[0] == 0
            assert conn.execute('SELECT count(*) FROM trujillo.incidents WHERE id=%s', (first['incident_id'],)).fetchone()[0] == 0
            print('OK: fotos atómicas, reintentos sin duplicados, conflictos y aislamiento RLS.')
        finally:
            conn.rollback()


if __name__ == '__main__':
    main()
