"""Exercise real HTTP report reads with RLS; all fixtures roll back."""
from contextlib import contextmanager
from datetime import datetime, timezone
from unittest.mock import patch
from uuid import uuid4
from fastapi.testclient import TestClient
from app.main import app
from app.auth import identity
from app.db import connect


def main():
    uid = 'history-test-' + str(uuid4())
    with connect() as conn:
        @contextmanager
        def same_transaction():
            yield conn
        try:
            app.dependency_overrides[identity] = lambda: {'sub': uid, 'name': 'Prueba historial'}
            with patch('app.reports.connect', same_transaction), TestClient(app) as client:
                response = client.post('/reports', json=dict(request_id=str(uuid4()), category='Auxilio', place='Prueba historial', description='', latitude=-20.123, longitude=-70.123, occurred_at=datetime.now(timezone.utc).isoformat()))
                assert response.status_code == 200, f'POST status {response.status_code}'
                report_id = response.json()['id']
                history = client.get('/reports')
                assert history.status_code == 200, f'History status {history.status_code}'
                assert len(history.json()) == 1 and history.json()[0]['id'] == report_id
                assert client.get('/reports/' + report_id).status_code == 200
                app.dependency_overrides[identity] = lambda: {'sub': uid + '-other'}
                assert client.get('/reports').json() == []
                assert client.get('/reports/' + report_id).status_code == 404
            print('OK: envio, historial y detalle HTTP; otra cuenta no puede leerlos.')
        finally:
            app.dependency_overrides.clear()
            conn.rollback()

if __name__ == '__main__':
    main()
