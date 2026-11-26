from unittest.mock import patch, MagicMock
from uuid import uuid4
import hashlib

import psycopg
import pytest
from fastapi.testclient import TestClient
from app.auth import identity
from app.main import app

client = TestClient(app)
sid = str(uuid4())
token = 'x' * 43
event = {'request_id': str(uuid4()), 'confidence': .95, 'modelVersion': 'test'}


@pytest.fixture
def signed():
    app.dependency_overrides[identity] = lambda: {'sub': 'operator'}
    yield
    app.dependency_overrides.clear()


@pytest.mark.parametrize('method,path', [('get', '/config'), ('get', '/cases'),
    ('post', '/sessions'), ('post', f'/sessions/{sid}/stop'), ('post', f'/cases/{sid}/decisions')])
def test_operator_identity_required(method, path):
    with patch('app.ai_simulation.execute') as db:
        assert getattr(client, method)('/operator/ai/simulation' + path).status_code == 401
        db.assert_not_called()


def test_session_exposes_only_scoped_token(signed):
    with patch('app.ai_simulation.execute', return_value={'id': sid, 'expiresAt': 'test'}) as db:
        result = client.post('/operator/ai/simulation/sessions', json={'cameraId': 'phone', 'latitude': -8.1, 'longitude': -79.0})
        assert result.status_code == 200
        secret = result.json()['workerToken']
        assert len(secret) >= 40
        assert db.call_args.args[2][-1] == hashlib.sha256(secret.encode()).hexdigest()
        assert result.headers['cache-control'] == 'private, no-store'


def test_worker_requires_secret():
    with patch('app.ai_simulation.connect') as db:
        assert client.post(f'/operator/ai/simulation/sessions/{sid}/events', json=event).status_code == 401
        assert client.post(f'/operator/ai/simulation/sessions/{sid}/events', json=event, headers={'Authorization': 'Bearer short'}).status_code == 401
        db.assert_not_called()


@pytest.mark.parametrize('error,status', [(psycopg.errors.InvalidAuthorizationSpecification, 401),
    (psycopg.errors.InsufficientPrivilege, 403), (psycopg.errors.RaiseException, 409),
    (RuntimeError, 503)])
def test_worker_errors_are_redacted(error, status):
    with patch('app.ai_simulation.connect', side_effect=error('secret-data')):
        response = client.post(f'/operator/ai/simulation/sessions/{sid}/events', json=event, headers={'Authorization': 'Bearer '+token})
        assert response.status_code == status
        assert 'secret-data' not in response.text


def test_worker_posts_score_without_firebase():
    db = MagicMock()
    db.__enter__.return_value.execute.return_value.fetchone.return_value = [{'status': 'created', 'case': {'id': sid}}]
    with patch('app.ai_simulation.connect', return_value=db):
        result = client.post(f'/operator/ai/simulation/sessions/{sid}/events', json=event, headers={'Authorization': 'Bearer '+token})
        assert result.status_code == 200
        assert result.json()['status'] == 'created'
        params = db.__enter__.return_value.execute.call_args.args[1]
        assert params[1] == hashlib.sha256(token.encode()).hexdigest()


@pytest.mark.parametrize('patch_data', [{'confidence': 2}, {'confidence': True}, {'modelVersion': ''},
    {'role': 'operator'}, {'latitude': -8.1}, {'request_id': 'invalid'}])
def test_worker_cannot_spoof_identity_location_or_invalid_score(patch_data):
    with patch('app.ai_simulation.connect') as db:
        response = client.post(f'/operator/ai/simulation/sessions/{sid}/events', json={**event, **patch_data}, headers={'Authorization': 'Bearer '+token})
        assert response.status_code == 422
        db.assert_not_called()


def test_session_validation_and_decisions(signed):
    with patch('app.ai_simulation.execute') as db:
        assert client.post('/operator/ai/simulation/sessions', json={'cameraId':'phone','latitude':91,'longitude':0}).status_code == 422
        assert client.post(f'/operator/ai/simulation/cases/{sid}/decisions', json={'stage':'Cerrada','reason':' '}).status_code == 422
        db.assert_not_called()
    with patch('app.ai_simulation.execute', return_value={'stage':'En revisión'}) as db:
        result = client.post(f'/operator/ai/simulation/cases/{sid}/decisions', json={'stage':'En revisión','reason':'Atendido en simulación'})
        assert result.status_code == 200
        assert db.call_args.args[2][1:] == ('En revisión','Atendido en simulación')
