from unittest.mock import patch
import psycopg
import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.auth import identity

client = TestClient(app)
payload = dict(schemaVersion=1, type='aggression_candidate', id='event-1',
               cameraId='camera-1', modelVersion='pilot', confidence=.82,
               latitude=-8.11, longitude=-79.02, detectedAt='2026-01-01T00:00:00Z')


@pytest.fixture
def signed():
    app.dependency_overrides[identity] = lambda: {'sub': 'operator'}
    yield
    app.dependency_overrides.clear()


@pytest.mark.parametrize('method,path', [('get', '/operator/ai/candidates'),
    ('post', '/operator/ai/candidates'), ('post', '/operator/ai/candidates/1/decisions')])
def test_identity_required(method, path):
    with patch('app.ai.execute') as db:
        assert getattr(client, method)(path).status_code == 401
        db.assert_not_called()


@pytest.mark.parametrize('change', [dict(confidence=1.1), dict(latitude=91),
    dict(confidence=True), dict(schemaVersion=True), dict(schemaVersion=2),
    dict(cameraId=' '), dict(detectedAt='2026-01-01T00:00:00'),
    dict(detectedAt='9999-01-01T00:00:00Z'), dict(detectedAt=1234),
    dict(role='admin'), dict(status='confirmed')])
def test_invalid_candidates_do_not_reach_db(signed, change):
    with patch('app.ai.execute') as db:
        assert client.post('/operator/ai/candidates', json={**payload, **change}).status_code == 422
        db.assert_not_called()


def test_ingest_preserves_contract(signed):
    with patch('app.ai.execute', return_value={**payload, 'sequence': 1, 'status': 'pending'}) as db:
        response = client.post('/operator/ai/candidates', json=payload)
        assert response.status_code == 200
        assert response.headers['cache-control'] == 'private, no-store'
        assert db.call_args.args[2][0].obj == payload


def test_pagination_has_no_overlap(signed):
    with patch('app.ai.execute', return_value=[{'sequence': 5}, {'sequence': 4}, {'sequence': 3}]) as db:
        result = client.get('/operator/ai/candidates?limit=2&before=6').json()
        assert result == {'items': [{'sequence': 5}, {'sequence': 4}], 'nextCursor': 4}
        assert db.call_args.args[2] == (6, 3)
    with patch('app.ai.execute', return_value=[{'sequence': 3}]):
        assert client.get('/operator/ai/candidates?limit=2&before=4').json()['nextCursor'] is None


@pytest.mark.parametrize('query', ['limit=0', 'limit=101', 'before=-1', 'before=9223372036854775808'])
def test_invalid_pagination(signed, query):
    with patch('app.ai.execute') as db:
        assert client.get('/operator/ai/candidates?' + query).status_code == 422
        db.assert_not_called()


@pytest.mark.parametrize('error,status', [(psycopg.errors.InsufficientPrivilege, 403),
    (psycopg.errors.NoDataFound, 404), (psycopg.errors.RaiseException, 409)])
def test_decision_errors_redacted(signed, error, status):
    with patch('app.workflows.connect', side_effect=error('private information')):
        response = client.post('/operator/ai/candidates/1/decisions', json={'decision': 'confirmed', 'reason': 'Revisado en cámara'})
        assert response.status_code == status
        assert 'private information' not in response.text


def test_invalid_decision(signed):
    with patch('app.ai.execute') as db:
        for body in [{'decision': 'pending', 'reason': 'Revisado'}, {'decision': 'confirmed', 'reason': '  '}]:
            assert client.post('/operator/ai/candidates/1/decisions', json=body).status_code == 422
        db.assert_not_called()
