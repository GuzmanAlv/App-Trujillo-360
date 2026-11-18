from unittest.mock import patch, AsyncMock, MagicMock
from uuid import uuid4
import jwt
import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from app.main import app
from app.auth import identity

client = TestClient(app)
CALL = str(uuid4())
SECRET = 'test-only-not-a-real-secret-1234567890'

@pytest.fixture
def signed(monkeypatch):
    app.dependency_overrides[identity] = lambda: {'sub': 'citizen'}
    monkeypatch.setenv('LIVEKIT_URL', 'wss://example.livekit.cloud')
    monkeypatch.setenv('LIVEKIT_API_KEY', 'test-key')
    monkeypatch.setenv('LIVEKIT_API_SECRET', SECRET)
    yield
    app.dependency_overrides.clear()

@pytest.mark.parametrize('operation', ['start', 'accept', 'token', 'end'])
def test_auth_required(operation):
    with patch('app.calls.action') as db:
        assert client.post(f'/calls/{CALL}/{operation}').status_code == 401
        db.assert_not_called()

def test_join_token_is_private_audio_only(signed):
    with patch('app.calls.action', return_value={'participant': 'internal-user-id'}) as db:
        response = client.post(f'/calls/{CALL}/token')
    db.assert_called_once()
    assert db.call_args.args[1] == 'token'
    assert response.status_code == 200
    assert response.headers['cache-control'] == 'private, no-store'
    claims = jwt.decode(response.json()['token'], SECRET, algorithms=['HS256'])
    assert claims['sub'] == 'internal-user-id'
    assert claims['exp'] - claims['nbf'] == 60
    assert claims['video']['room'] == f'sos-{CALL}'
    assert claims['video']['canPublishSources'] == ['microphone']
    assert claims['video']['canPublishData'] is False
    assert SECRET not in response.text

def test_denial_never_mints_token(signed):
    with patch('app.calls.action', side_effect=HTTPException(403, 'No autorizado')), patch('app.calls.api.AccessToken') as token:
        assert client.post(f'/calls/{CALL}/token').status_code == 403
        token.assert_not_called()

def test_missing_configuration_does_not_create_call(signed, monkeypatch):
    monkeypatch.delenv('LIVEKIT_API_SECRET')
    with patch('app.calls.action') as db:
        assert client.post(f'/calls/{CALL}/start').status_code == 503
        db.assert_not_called()

def test_end_deletes_room_after_database_authorizes(signed):
    live = MagicMock()
    live.__aenter__ = AsyncMock(return_value=live)
    live.__aexit__ = AsyncMock(return_value=False)
    live.room.delete_room = AsyncMock()
    with patch('app.calls.action', return_value={'state': 'ended', 'participant': 'hidden'}), patch('app.calls.api.LiveKitAPI', return_value=live):
        response = client.post(f'/calls/{CALL}/end')
    assert response.json() == {'state': 'ended'}
    assert live.room.delete_room.call_args.args[0].room == f'sos-{CALL}'
