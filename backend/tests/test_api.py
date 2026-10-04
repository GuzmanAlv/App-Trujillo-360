from unittest.mock import patch
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)


def test_health_without_database():
    assert client.get('/health').json() == {'status': 'ok'}


def test_database_error_is_redacted():
    with patch('app.main.connect', side_effect=RuntimeError('secret-password')):
        response = client.get('/ready')
    assert response.status_code == 503
    assert 'secret' not in response.text


def test_no_unauthenticated_writes():
    for resource in ('users', 'reports', 'incidents', 'reviews'):
        assert client.post('/' + resource, json={}).status_code == 404
