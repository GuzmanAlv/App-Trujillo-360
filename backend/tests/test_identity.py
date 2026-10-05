from unittest.mock import patch
import time
import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.auth import verify_token

client = TestClient(app)

def test_missing_token():
    assert client.get('/me').status_code == 401

def test_invalid_token_never_connects_database():
    with patch('app.auth.verify_token', side_effect=ValueError('private')), patch('app.main.connect') as db:
        response = client.get('/me', headers={'Authorization': 'Bearer invalid'})
    assert response.status_code == 401
    assert 'private' not in response.text
    db.assert_not_called()

@pytest.mark.parametrize('change', [
    {'iss': 'https://example.com'}, {'sub': ''}, {'email_verified': False},
    {'firebase': {'sign_in_provider': 'password'}}, {'auth_time': time.time()+3600},
])
def test_rejects_wrong_identity(change, monkeypatch):
    monkeypatch.setenv('FIREBASE_PROJECT_ID', 'test-project')
    claims = dict(iss='https://securetoken.google.com/test-project', sub='uid',
                  email_verified=True, firebase={'sign_in_provider': 'google.com'}, auth_time=1)
    claims.update(change)
    with patch('app.auth.id_token.verify_firebase_token', return_value=claims):
        with pytest.raises(ValueError):
            verify_token('signed-token')

def test_project_is_pinned(monkeypatch):
    monkeypatch.setenv('FIREBASE_PROJECT_ID', 'test-project')
    claims = dict(iss='https://securetoken.google.com/test-project', sub='uid',
                  email_verified=True, firebase={'sign_in_provider': 'google.com'}, auth_time=1)
    with patch('app.auth.id_token.verify_firebase_token', return_value=claims) as verifier:
        assert verify_token('signed-token')['sub'] == 'uid'
        assert verifier.call_args.kwargs['audience'] == 'test-project'

def test_certificate_transport_accepts_positional_url(monkeypatch):
    monkeypatch.setenv('FIREBASE_PROJECT_ID', 'test-project')
    with patch('app.auth.Request') as request, patch('app.auth.id_token.verify_firebase_token') as verifier:
        def fetch(token, transport, audience):
            transport('https://example.com/certs', method='GET')
            raise ValueError('stop after transport')
        verifier.side_effect = fetch
        with pytest.raises(ValueError):
            verify_token('test')
        request.return_value.assert_called_once_with('https://example.com/certs', method='GET', timeout=10)
