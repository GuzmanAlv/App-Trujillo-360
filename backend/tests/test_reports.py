from datetime import datetime, timezone, timedelta
from uuid import uuid4
from unittest.mock import patch
import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.auth import identity

@pytest.fixture
def client():
    app.dependency_overrides[identity] = lambda: {'sub': 'test-uid', 'name':'Prueba'}
    yield TestClient(app)
    app.dependency_overrides.clear()

def payload():
    return dict(request_id=str(uuid4()),category='Robo',place='Prueba',description='',
                latitude=-8.11,longitude=-79.02,occurred_at=datetime.now(timezone.utc).isoformat())

@pytest.mark.parametrize('change', [
    {'latitude':91}, {'longitude':181}, {'category':'Inventado'}, {'place':'  '},
    {'description':'x'*501}, {'user_id':'otro'}, {'occurred_at':'2026-01-01T10:00:00'},
    {'occurred_at': (datetime.now(timezone.utc)+timedelta(days=1)).isoformat()},
])
def test_invalid_reports_never_reach_database(client, change):
    data=payload(); data.update(change)
    with patch('app.reports.connect') as connection:
        assert client.post('/reports', json=data).status_code == 422
        connection.assert_not_called()

def test_storage_failure_is_not_success(client):
    with patch('app.reports.connect', side_effect=RuntimeError('secret')):
        response=client.post('/reports',json=payload())
        assert response.status_code==503
        assert 'secret' not in response.text
