import base64
import io
from datetime import datetime, timezone
from uuid import uuid4
from unittest.mock import patch
import pytest
from PIL import Image
from fastapi.testclient import TestClient
from app.main import app
from app.auth import identity
from app.photos import PhotoInput, normalize_photo


def image_payload():
    data = io.BytesIO()
    image = Image.new('RGB', (32, 24), 'red')
    exif = Image.Exif()
    exif[270] = 'Private metadata'
    image.save(data, format='JPEG', exif=exif)
    return {'id': str(uuid4()), 'content_base64': base64.b64encode(data.getvalue()).decode()}


@pytest.fixture
def client():
    app.dependency_overrides[identity] = lambda: {'sub': 'owner', 'name': 'Prueba'}
    yield TestClient(app)
    app.dependency_overrides.clear()


def report(photos):
    return dict(request_id=str(uuid4()), category='Robo', place='Prueba', description='',
                latitude=-8.11, longitude=-79.02, occurred_at=datetime.now(timezone.utc).isoformat(), photos=photos)


def test_photo_is_valid_jpeg_without_original_metadata():
    payload = image_payload()
    first = normalize_photo(PhotoInput(**payload))
    assert first == normalize_photo(PhotoInput(**payload))
    with Image.open(io.BytesIO(base64.b64decode(first['content_base64']))) as image:
        assert image.format == 'JPEG'
        assert not image.getexif()
        image.load()


@pytest.mark.parametrize('photos', [
    [{'id': str(uuid4()), 'content_base64': 'not an image'}],
    [{'id': str(uuid4()), 'content_base64': base64.b64encode(b'<svg>fake</svg>').decode()}],
    [image_payload() for _ in range(4)],
])
def test_bad_photos_do_not_reach_database(client, photos):
    with patch('app.reports.connect') as database:
        assert client.post('/reports', json=report(photos)).status_code == 422
        database.assert_not_called()


def test_duplicate_photo_ids_rejected(client):
    photo = image_payload()
    with patch('app.reports.connect') as database:
        assert client.post('/reports', json=report([photo, photo])).status_code == 422
        database.assert_not_called()


def test_valid_photo_is_saved_with_report_in_one_database_operation(client):
    data = report([image_payload()])
    saved = {'id': str(uuid4()), 'request_id': data['request_id'], 'photo_count': 1, 'status': 'pending'}
    with patch('app.reports.connect') as connection:
        database = connection.return_value.__enter__.return_value
        database.execute.return_value.fetchone.return_value = (saved,)
        response = client.post('/reports', json=data)
        assert response.status_code == 200
        assert response.json() == saved
        query, arguments = database.execute.call_args.args
        assert 'submit_report_with_photos' in query
        normalized = arguments[-1].obj
        assert len(normalized) == 1
        assert normalized[0]['id'] == data['photos'][0]['id']
        assert base64.b64decode(normalized[0]['content_base64']).startswith(b'\xff\xd8')


def test_total_body_limit(client):
    with patch('app.reports.connect') as database:
        response = client.post('/reports', content=b' ' * (9 * 1024 * 1024 + 1))
        assert response.status_code == 413
        database.assert_not_called()


def test_detail_requires_identity():
    assert TestClient(app).get('/reports/' + str(uuid4())).status_code == 401


def test_detail_hides_unavailable_report(client):
    with patch('app.reports.connect') as connection:
        cursor = connection.return_value.__enter__.return_value.cursor.return_value.__enter__.return_value
        cursor.fetchone.return_value = None
        assert client.get('/reports/' + str(uuid4())).status_code == 404
