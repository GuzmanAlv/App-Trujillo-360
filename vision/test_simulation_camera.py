import base64
from datetime import datetime, timedelta, timezone
from io import BytesIO
from unittest.mock import Mock, patch
from uuid import uuid4

from fastapi.testclient import TestClient
from PIL import Image
import httpx
import pytest

from simulation_camera import BackendPublisher, create_app


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
