"""Check community image authorization with real SQL/HTTP; all fixtures roll back."""
import base64
import io
from contextlib import contextmanager
from datetime import datetime, timezone
from uuid import uuid4
from unittest.mock import patch
import psycopg
from PIL import Image
from fastapi.testclient import TestClient
from app.main import app
from app.auth import identity
from app.db import connect

class RollbackCheck(Exception): pass

def main():
    image = io.BytesIO()
    Image.new('RGB', (16,16), 'blue').save(image, 'PNG')
    photo_id = str(uuid4())
    prefix = 'community-photo-' + str(uuid4())
    selected = {'uid': prefix+'0'}
    with connect() as conn:
        @contextmanager
        def same_transaction(): yield conn
        try:
            app.dependency_overrides[identity] = lambda: {'sub': selected['uid'], 'name': 'Prueba'}
            with patch('app.reports.connect', same_transaction), TestClient(app) as client:
                def check_error(path, status):
                    try:
                        with conn.transaction():
                            response = client.get(path)
                            assert response.status_code == status, f'Expected {status}, got {response.status_code}'
                            raise RollbackCheck()
                    except RollbackCheck: pass
                groups = []
                report_id = None
                for latitude in (-32.123,-32.125):
                    group = None
                    for account in range(3):
                        selected['uid'] = prefix+str(account)
                        photos = [{'id':photo_id,'content_base64':base64.b64encode(image.getvalue()).decode()}] if latitude==-32.123 and account==0 else []
                        response = client.post('/reports', json=dict(request_id=str(uuid4()), category='Robo', place='Prueba', description='Privado', latitude=latitude, longitude=-62.123, occurred_at=datetime.now(timezone.utc).isoformat(), photos=photos))
                        assert response.status_code == 200, f'Submit {response.status_code}'
                        data = response.json()
                        group = group or data['incident_id']
                        assert data['incident_id'] == group
                        if photos: report_id = data['id']
                        if account < 2:
                            check_error(f'/incidents/{group}/photos',404)
                            check_error(f'/incidents/{group}/photos/{photo_id}',404)
                    groups.append(group)
                # An active unrelated account can see only corroborated images.
                selected['uid'] = prefix+'outsider'
                response = client.post('/reports', json=dict(request_id=str(uuid4()), category='Auxilio', place='Prueba', description='', latitude=-33, longitude=-63, occurred_at=datetime.now(timezone.utc).isoformat()))
                assert response.status_code == 200
                metadata = client.get(f'/incidents/{groups[0]}/photos')
                assert metadata.status_code == 200 and metadata.json() == [{'id':photo_id, 'report_id':report_id}]
                binary = client.get(f'/incidents/{groups[0]}/photos/{photo_id}')
                assert binary.status_code == 200
                assert binary.headers['cache-control'] == 'private, no-store'
                Image.open(io.BytesIO(binary.content)).verify()
                check_error(f'/incidents/{groups[1]}/photos/{photo_id}',404)
                check_error(f'/reports/{report_id}',404)
                selected['uid'] = prefix+'unknown'
                check_error(f'/incidents/{groups[0]}/photos',403)
                check_error(f'/incidents/{groups[0]}/photos/{photo_id}',403)
                print('OK: fotos ocultas con 1/2 cuentas, visibles con 3, sin identidades, fotos de otro grupo y reportes privados protegidos.')
        finally:
            app.dependency_overrides.clear()
            conn.rollback()

if __name__ == '__main__': main()
