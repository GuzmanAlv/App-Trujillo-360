from datetime import datetime, timezone, timedelta
from uuid import uuid4
from unittest.mock import patch
import pytest
import psycopg
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


@pytest.mark.parametrize('query', [
    'latitude=91&longitude=0', 'latitude=0&longitude=181',
    'latitude=nan&longitude=0', 'latitude=0&longitude=0&radius=3001',
])
def test_invalid_nearby_query_never_reaches_database(client, query):
    with patch('app.reports.connect') as connection:
        assert client.get('/incidents/nearby?' + query).status_code == 422
        connection.assert_not_called()


def test_nearby_failure_is_not_empty_success(client):
    with patch('app.reports.connect', side_effect=RuntimeError('secret')):
        response = client.get('/incidents/nearby?latitude=-8.11&longitude=-79.02')
        assert response.status_code == 503
        assert 'secret' not in response.text


def test_account_history_uses_authenticated_database_context(client):
    from unittest.mock import MagicMock
    connection = MagicMock()
    cursor = connection.__enter__.return_value.cursor.return_value.__enter__.return_value
    cursor.fetchall.return_value = []
    with patch('app.reports.connect', return_value=connection):
        response = client.get('/reports')
    assert response.status_code == 200
    assert response.json() == []
    assert response.headers['cache-control'] == 'private, no-store'
    connection.__enter__.return_value.execute.assert_called_once_with(
        "SELECT set_config('app.firebase_uid', %s, true)", ('test-uid',))


def test_account_history_failure_is_not_empty_success(client):
    with patch('app.reports.connect', side_effect=RuntimeError('secret')):
        response = client.get('/reports')
    assert response.status_code == 503
    assert 'secret' not in response.text


@pytest.mark.parametrize('query', [
    'south=-91&north=0&west=0&east=1',
    'south=0&north=-1&west=0&east=1',
    'south=0&north=1&west=nan&east=1',
    'south=0&north=1&west=-181&east=1',
])
def test_invalid_map_bounds_never_reach_database(client, query):
    with patch('app.reports.connect') as connection:
        assert client.get('/incidents/map?' + query).status_code == 422
        connection.assert_not_called()


def test_map_failure_does_not_return_empty_success(client):
    with patch('app.reports.connect', side_effect=RuntimeError('secret')):
        response = client.get('/incidents/map?south=-9&north=-8&west=-80&east=-79')
    assert response.status_code == 503
    assert 'secret' not in response.text


@pytest.mark.parametrize('error,status', [(psycopg.errors.NoDataFound(),404), (psycopg.errors.InsufficientPrivilege(),403), (RuntimeError('secret'),503)])
def test_grouped_reports_errors_are_protected(client, error, status):
    with patch('app.reports.connect', side_effect=error):
        response = client.get(f'/incidents/{uuid4()}/reports')
    assert response.status_code == status
    assert 'secret' not in response.text


def test_invalid_group_id_never_reaches_database(client):
    with patch('app.reports.connect') as connection:
        assert client.get('/incidents/not-a-uuid/reports').status_code == 422
        connection.assert_not_called()


@pytest.mark.parametrize('suffix', ['photos', 'photos/'+str(uuid4())])
@pytest.mark.parametrize('error,status', [(psycopg.errors.NoDataFound(),404), (psycopg.errors.InsufficientPrivilege(),403), (RuntimeError('secret'),503)])
def test_community_photos_errors_are_protected(client, suffix, error, status):
    with patch('app.reports.connect', side_effect=error):
        response = client.get(f'/incidents/{uuid4()}/{suffix}')
    assert response.status_code == status
    assert 'secret' not in response.text
