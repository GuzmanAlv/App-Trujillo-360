import base64
from datetime import datetime, timedelta, timezone
from io import BytesIO
from unittest.mock import Mock, patch
from uuid import uuid4

from fastapi.testclient import TestClient
from PIL import Image
import httpx
import pytest

from simulation_camera import BackendPublisher, CameraAccess, SessionPublisher, create_app


def session_access(**changes):
    return {'schemaVersion': 1, 'id': str(uuid4()), 'workerToken': 'x' * 43,
            'expiresAt': (datetime.now(timezone.utc)+timedelta(minutes=29)).isoformat(), **changes}


def test_standby_configure_renew_without_reloading_model_or_exposing_token():
    publisher = SessionPublisher('https://api.example')
    scorer = Mock(return_value=.72)
    proxy = TestClient(create_app('local-pair', scorer, publisher))
    headers = {'X-Pairing-Token': 'local-pair'}
    assert proxy.get('/api/session', headers=headers).json()['sessionReady'] is False
    assert proxy.post('/api/analyze', json=batch(), headers=headers).status_code == 410
    scorer.assert_not_called()
    first = session_access()
    assert proxy.post('/api/session', json=first).status_code == 401
    assert not publisher.ready()
    response = proxy.post('/api/session', json=first, headers=headers)
    assert response.status_code == 200 and first['workerToken'] not in response.text
    first_binding = response.json()['binding']
    headers['X-Camera-Binding'] = first_binding
    assert proxy.get('/api/session', headers=headers).json()['sessionReady'] is True
    second = session_access()
    response = proxy.post('/api/session', json=second, headers=headers)
    assert response.status_code == 200
    assert proxy.post('/api/analyze', json=batch(), headers=headers).status_code == 409
    assert proxy.get('/api/session', headers=headers).json()['sessionReady'] is False
    headers['X-Camera-Binding'] = response.json()['binding']
    with patch('simulation_camera.httpx.post', return_value=httpx.Response(200, json={'status': 'below_threshold', 'case': None})) as post:
        result = proxy.post('/api/analyze', json=batch(), headers=headers)
    assert result.status_code == 200
    assert second['id'] in post.call_args.args[0]
    scorer.assert_called_once()
    assert second['workerToken'] not in result.text


def test_standby_rejects_expired_access_and_clears_rejected_credentials():
    publisher = SessionPublisher('https://api.example')
    proxy = TestClient(create_app('local-pair', Mock(), publisher))
    headers = {'X-Pairing-Token': 'local-pair'}
    expired = session_access(expiresAt=(datetime.now(timezone.utc)-timedelta(seconds=1)).isoformat())
    assert proxy.post('/api/session', json=expired, headers=headers).status_code == 410
    assert not publisher.ready()
    publisher.configure(CameraAccess(**session_access()))
    with patch('simulation_camera.httpx.post', return_value=httpx.Response(409)):
        with pytest.raises(Exception) as raised:
            publisher(.8, uuid4())
    assert raised.value.status_code == 409
    assert not publisher.ready()


def test_private_https_proxy_accepts_only_configured_host_and_origin():
    app = create_app('local-pair', Mock(return_value=.9), Mock(return_value={'status': 'warming_up', 'case': None}),
                     public_origin='https://rtx.example.ts.net')
    proxy = TestClient(app, base_url='http://rtx.example.ts.net')
    response = proxy.post('/api/analyze', json=batch(), headers={
        'Origin': 'https://rtx.example.ts.net', 'X-Pairing-Token': 'local-pair'})
    assert response.status_code == 200
    assert proxy.get('/health').json()['status'] == 'ok'
    assert proxy.get('/health', headers={'Host': 'unknown.ts.net'}).status_code == 400
    assert proxy.post('/api/analyze', json=batch(), headers={
        'Origin': 'https://unknown.ts.net', 'X-Pairing-Token': 'local-pair'}).status_code == 403
    assert proxy.post('/api/analyze', json=batch()).status_code == 401


def test_connection_check_never_calls_model_or_backend():
    scorer, publisher = Mock(), Mock()
    proxy = TestClient(create_app('local-pair', scorer, publisher, connection_test=True))
    assert proxy.get('/health').json() == {'status': 'ok', 'mode': 'connection_test'}
    assert 'Prueba de conexión' in proxy.get('/').text
    assert proxy.post('/api/analyze', json=batch(), headers={'X-Pairing-Token': 'local-pair'}).status_code == 409
    scorer.assert_not_called()
    publisher.assert_not_called()


@pytest.mark.parametrize('origin', ['http://rtx.ts.net', 'https://rtx.ts.net/path',
    'https://user:password@rtx.ts.net', 'https://rtx.ts.net?query=yes', 'https://rtx.ts.net:1234'])
def test_public_origin_cannot_broaden_trust(origin):
    with pytest.raises(ValueError):
        create_app('local-pair', Mock(), Mock(), public_origin=origin)


def batch(size=(224, 224)):
    stream = BytesIO()
    Image.new('RGB', size, color=(40, 50, 60)).save(stream, format='JPEG')
    frame = base64.b64encode(stream.getvalue()).decode()
    return {'frames': [frame] * 32, 'offsets_ms': [index * 125 for index in range(32)]}


def client(scorer=None, publisher=None, **kwargs):
    return TestClient(create_app('local-pair', scorer or Mock(return_value=.9),
                                publisher or Mock(return_value={'status': 'warming_up', 'case': None}), **kwargs))


def test_unpaired_requests_never_reach_model():
    scorer, publisher = Mock(), Mock()
    response = client(scorer, publisher).post('/api/analyze', json=batch())
    assert response.status_code == 401
    scorer.assert_not_called()
    publisher.assert_not_called()


def test_expired_pairing_never_reaches_model():
    scorer = Mock()
    response = client(scorer, expires_at=datetime.now(timezone.utc)-timedelta(seconds=1)).post(
        '/api/analyze', json=batch(), headers={'X-Pairing-Token': 'local-pair'})
    assert response.status_code == 410
    scorer.assert_not_called()


def test_wrong_origin_is_rejected():
    response = client().post('/api/analyze', json=batch(), headers={
        'X-Pairing-Token': 'local-pair', 'Origin': 'https://untrusted.example'})
    assert response.status_code == 403


def test_frame_inference_result_not_browser_score_is_published():
    scorer = Mock(return_value=.93)
    publisher = Mock(return_value={'status': 'created', 'case': {'id': 'test-case'}})
    response = client(scorer, publisher).post('/api/analyze', json=batch(), headers={'X-Pairing-Token': 'local-pair'})
    assert response.status_code == 200
    assert response.json()['result']['case']['id'] == 'test-case'
    frames = scorer.call_args.args[0]
    assert len(frames) == 32 and frames[0].shape == (224, 224, 3)
    assert publisher.call_args.args[0] == .93
    assert response.json()['confidence'] == .93


@pytest.mark.parametrize('change', [
    {'frames': ['bad'] * 32},
    {'offsets_ms': [0] * 32},
    {'offsets_ms': [index * 20 for index in range(32)]},
    {'offsets_ms': [index * 400 for index in range(32)]},
    {'frames': batch()['frames'][:31]},
    {'confidence': .99},
])
def test_malformed_sequences_never_reach_model(change):
    scorer = Mock()
    response = client(scorer).post('/api/analyze', json={**batch(), **change}, headers={'X-Pairing-Token': 'local-pair'})
    assert response.status_code == 422
    scorer.assert_not_called()


def test_image_dimensions_are_checked_before_model():
    scorer = Mock()
    response = client(scorer).post('/api/analyze', json=batch((512, 512)), headers={'X-Pairing-Token': 'local-pair'})
    assert response.status_code == 422
    scorer.assert_not_called()


def test_body_limit_is_enforced_before_model():
    scorer = Mock()
    response = client(scorer).post('/api/analyze', content=b'x' * (3*1024*1024+1), headers={'X-Pairing-Token': 'local-pair'})
    assert response.status_code == 413
    scorer.assert_not_called()


def test_backend_retry_preserves_request_uuid_and_redacts_secrets():
    publisher = BackendPublisher('https://api.example', uuid4(), 'private-worker-token')
    request_id = uuid4()
    response = httpx.Response(200, json={'status': 'cooldown', 'case': None})
    with patch('simulation_camera.httpx.post', side_effect=[httpx.ConnectError('network secret'), response]) as post:
        assert publisher(.9, request_id)['status'] == 'cooldown'
        assert post.call_args_list[0].kwargs['json'] == post.call_args_list[1].kwargs['json']
        assert post.call_args.kwargs['json']['request_id'] == str(request_id)


def test_gpu_errors_do_not_publish_or_leak():
    publisher = Mock()
    response = client(Mock(side_effect=RuntimeError('private GPU details')), publisher).post(
        '/api/analyze', json=batch(), headers={'X-Pairing-Token': 'local-pair'})
    assert response.status_code == 503 and 'private' not in response.text
    publisher.assert_not_called()


def test_backend_url_rejects_credentials_and_remote_http():
    for url in ('http://remote.example', 'https://user:password@api.example', 'https://api.example?token=secret'):
        with pytest.raises(ValueError):
            BackendPublisher(url, uuid4(), 'secret')


def test_camera_page_contains_no_worker_credential():
    page = client().get('/')
    assert page.status_code == 200 and 'getUserMedia' in page.text
    assert 'TRUJILLO_SIM_TOKEN' not in page.text
    assert page.headers['cache-control'] == 'no-store'
