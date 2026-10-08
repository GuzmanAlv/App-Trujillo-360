"""Real restricted-role grouping and HTTP visibility checks; fixtures always roll back."""
from contextlib import contextmanager
from datetime import datetime, timezone, timedelta
from unittest.mock import patch
from uuid import uuid4
import psycopg
from fastapi.testclient import TestClient
from app.main import app
from app.auth import identity
from app.db import connect


def main():
    prefix = 'community-test-' + str(uuid4())
    selected = {'uid': prefix+'0'}
    timestamp = datetime.now(timezone.utc) - timedelta(minutes=20)
    with connect() as conn:
        @contextmanager
        def same_transaction():
            yield conn
        try:
            app.dependency_overrides[identity] = lambda: {'sub': selected['uid'], 'name': 'Prueba comunidad'}
            with patch('app.reports.connect', same_transaction), TestClient(app) as client:
                ids = []
                incident = None
                for account in range(4):
                    selected['uid'] = prefix+str(account)
                    response = client.post('/reports', json=dict(request_id=str(uuid4()), category='Robo', place='Prueba', description='Privado', latitude=-30.123, longitude=-60.123, occurred_at=(timestamp+timedelta(seconds=account)).isoformat()))
                    assert response.status_code == 200, f'Submit {response.status_code}'
                    data = response.json()
                    incident = incident or data['incident_id']
                    assert data['incident_id'] == incident
                    assert data['corroboration_count'] == account+1
                    ids.append(data['id'])
                    view = client.get('/incidents/map?south=-30.124&north=-30.122&west=-60.124&east=-60.122')
                    assert view.status_code == 200
                    visible = [r for r in view.json() if r['id'] == incident]
                    assert len(visible) == (1 if account >= 2 else 0)
                    if account < 2:
                        try:
                            with conn.transaction():
                                conn.execute('SELECT * FROM trujillo.incident_reports(%s)', (incident,)).fetchall()
                        except psycopg.errors.NoDataFound:
                            pass
                        else:
                            raise AssertionError('Pending contributions exposed')
                contributions = client.get(f'/incidents/{incident}/reports')
                assert contributions.status_code == 200
                rows = contributions.json()
                assert {r['id'] for r in rows} == set(ids) and len(rows) == 4
                assert all(not ({'description', 'photos', 'user_id', 'auth_subject', 'display_name'} & set(r)) for r in rows)
                try:
                    with conn.transaction():
                        conn.execute('SELECT trujillo.submit_report(%s,%s,%s,%s,%s,%s,%s)',
                                     (uuid4(),'Robo','Prueba','Privado',-30.123,-60.123,timestamp+timedelta(seconds=5)))
                except psycopg.errors.NoDataFound:
                    pass
                else:
                    raise AssertionError('Same account counted twice')
                for category, latitude, delta in [('Auxilio',-30.123,5), ('Robo',-30.125,5), ('Robo',-30.123,16*60)]:
                    selected['uid'] = prefix+str(uuid4())
                    different = client.post('/reports', json=dict(request_id=str(uuid4()), category=category, place='Prueba', description='', latitude=latitude, longitude=-60.123, occurred_at=(timestamp+timedelta(seconds=delta)).isoformat()))
                    assert different.status_code == 200
                    assert different.json()['incident_id'] != incident
                    assert different.json()['corroboration_count'] == 1
                print('OK: 3 cuentas corroboran, 4 aportes agrupados, duplicados rechazados, reglas de tipo/100 m/15 min y privacidad.')
        finally:
            app.dependency_overrides.clear()
            conn.rollback()

if __name__ == '__main__':
    main()
