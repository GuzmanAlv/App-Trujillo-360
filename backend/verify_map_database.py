"""Verify separate map and proximity queries with real SQL; roll back all fixtures."""
from contextlib import contextmanager
from datetime import datetime, timezone
from unittest.mock import patch
from uuid import uuid4
from fastapi.testclient import TestClient
from app.main import app
from app.auth import identity
from app.db import connect


def main():
    uid = 'map-test-' + str(uuid4())
    with connect() as conn:
        @contextmanager
        def same_transaction():
            yield conn
        try:
            app.dependency_overrides[identity] = lambda: {'sub': uid, 'name': 'Prueba mapa'}
            with patch('app.reports.connect', same_transaction), TestClient(app) as client:
                ids = []
                for latitude in (-20.123, -20.15):
                    for account in range(3):
                        app.dependency_overrides[identity] = lambda account=account: {'sub': uid+str(account), 'name': 'Prueba mapa'}
                        response = client.post('/reports', json=dict(request_id=str(uuid4()), category='Auxilio', place='Prueba mapa', description='', latitude=latitude, longitude=-70.123, occurred_at=datetime.now(timezone.utc).isoformat()))
                        assert response.status_code == 200, f'POST status {response.status_code}'
                    ids.append(response.json()['incident_id'])
                nearby = client.get('/incidents/nearby?latitude=-20.123&longitude=-70.123&radius=1000')
                assert nearby.status_code == 200, f'Nearby status {nearby.status_code}'
                visible = {row['id'] for row in nearby.json()}
                assert ids[0] in visible and ids[1] not in visible
                map_view = client.get('/incidents/map?south=-20.16&north=-20.11&west=-70.14&east=-70.11')
                assert map_view.status_code == 200, f'Map status {map_view.status_code}'
                assert set(ids).issubset({row['id'] for row in map_view.json()})
                assert all('photos' not in row and 'ownerUid' not in row for row in map_view.json())
                moved = client.get('/incidents/map?south=-20.155&north=-20.145&west=-70.14&east=-70.11')
                assert moved.status_code == 200
                moved_ids = {row['id'] for row in moved.json()}
                assert ids[1] in moved_ids and ids[0] not in moved_ids
                app.dependency_overrides[identity] = lambda: {'sub': uid+'-unknown'}
                assert client.get('/incidents/map?south=-21&north=-20&west=-71&east=-70').status_code == 403
            print('OK: mapa por area, cerca a 1 km, permisos y resumen sin datos privados.')
        finally:
            app.dependency_overrides.clear()
            conn.rollback()

if __name__ == '__main__':
    main()
