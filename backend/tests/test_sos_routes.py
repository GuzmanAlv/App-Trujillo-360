from unittest.mock import Mock, patch
from uuid import uuid4

import pytest
import requests
from fastapi import HTTPException
from fastapi.testclient import TestClient
from app.main import app
from app.auth import identity
from app import sos_routes

client = TestClient(app)
CASE = str(uuid4())
PATH = f'/operator/sos-cases/{CASE}/route'
PREVIEW_PATH = f'/operator/sos-cases/{CASE}/preview-route'
ORIGIN = {'latitude': -8.12, 'longitude': -79.02}
CONFIRMED = dict(can_edit=True, decision='confirmed', attention='none',
                 latitude=-8.11, longitude=-79.03, category='Auxilio')


@pytest.fixture(autouse=True)
def setup(monkeypatch):
    monkeypatch.setenv('GOOGLE_ROUTES_API_KEY', 'test-secret')
    sos_routes._recent.clear()
    yield
    app.dependency_overrides.clear()
    sos_routes._recent.clear()


def login():
    app.dependency_overrides[identity] = lambda: {'sub': 'operator'}


def test_unauthenticated_never_queries_database_or_google():
    with patch('app.sos_routes.execute') as db, patch('app.sos_routes.requests.post') as google:
        assert client.post(PATH, json=ORIGIN).status_code == 401
        db.assert_not_called()
        google.assert_not_called()


@pytest.mark.parametrize('case,status', [
    ({**CONFIRMED, 'can_edit': False}, 403),
    ({**CONFIRMED, 'decision': 'pending'}, 409),
    ({**CONFIRMED, 'decision': 'discarded'}, 409),
    ({**CONFIRMED, 'attention': 'resolved'}, 409),
])
def test_only_assigned_operator_and_active_confirmed_case(case, status):
    login()
    with patch('app.sos_routes.execute', return_value=case), patch('app.sos_routes.requests.post') as google:
        assert client.post(PATH, json=ORIGIN).status_code == status
        google.assert_not_called()


def test_database_role_denial_cannot_call_google():
    login()
    with patch('app.sos_routes.execute', side_effect=HTTPException(403)), patch('app.sos_routes.requests.post') as google:
        assert client.post(PATH, json=ORIGIN).status_code == 403
        google.assert_not_called()


def test_preview_uses_caller_location_without_claiming_the_sos():
    login()
    offer = dict(CONFIRMED, decision='pending', available=True,
                 caller_latitude=-8.13, caller_longitude=-79.04)
    with patch('app.sos_routes.execute', return_value=offer) as db, patch('app.sos_routes.compute_route', return_value={}) as compute:
        assert client.post(PREVIEW_PATH, json=ORIGIN).status_code == 200
        assert 'operator_sos_map_data()' in db.call_args.args[1]
        assert 'claim_sos' not in db.call_args.args[1]
        assert compute.call_args.args[2] == {'latitude': -8.13, 'longitude': -79.04}
        assert compute.call_args.kwargs == {'preview': True}


@pytest.mark.parametrize('offer, status', [({}, 409), ({'can_edit': False}, 403),
    ({'can_edit': True, 'available': False, 'decision': 'pending'}, 409)])
def test_preview_rejects_unavailable_offers_before_calling_google(offer, status):
    login()
    with patch('app.sos_routes.execute', return_value=offer), patch('app.sos_routes.compute_route') as compute:
        assert client.post(PREVIEW_PATH, json=ORIGIN).status_code == status
        compute.assert_not_called()


@pytest.mark.parametrize('body', [
    {**ORIGIN, 'destination': {'latitude': 0, 'longitude': 0}},
    {**ORIGIN, 'latitude': 91}, {**ORIGIN, 'longitude': -181},
])
def test_origin_validation_and_no_client_destination(body):
    login()
    with patch('app.sos_routes.execute') as db:
        assert client.post(PATH, json=body).status_code == 422
        db.assert_not_called()


def test_missing_configuration_preserves_case(monkeypatch):
    login()
    monkeypatch.delenv('GOOGLE_ROUTES_API_KEY')
    with patch('app.sos_routes.execute', return_value=CONFIRMED) as db, patch('app.sos_routes.requests.post') as google:
        response = client.post(PATH, json=ORIGIN)
        assert response.json()['detail']['code'] == 'ROUTES_NOT_CONFIGURED'
        assert db.call_args_list[0].args[1] == 'SELECT trujillo.sos_case_read(%s)'
        assert all('SELECT trujillo.' in call.args[1] for call in db.call_args_list)
        google.assert_not_called()


def test_fastest_alternative_uses_canonical_destination_and_redacts_secret():
    login()
    result = Mock(status_code=200)
    result.json.return_value = {'routes': [
        {'duration': '120s', 'distanceMeters': 1000, 'polyline': {'encodedPolyline': 'slow'}},
        {'duration': '90.5s', 'distanceMeters': 1500, 'polyline': {'encodedPolyline': 'fast'}},
    ]}
    with patch('app.sos_routes.execute', return_value=CONFIRMED), patch('app.sos_routes.requests.post', return_value=result) as google:
        response = client.post(PATH, json=ORIGIN)
        assert response.status_code == 200
        assert response.headers['cache-control'] == 'private, no-store'
        assert response.json()['encoded_polyline'] == 'fast'
        assert response.json()['duration_seconds'] == 90.5
        assert 'test-secret' not in response.text
        kwargs = google.call_args.kwargs
        assert kwargs['json']['destination']['location']['latLng'] == {'latitude': -8.11, 'longitude': -79.03}
        assert kwargs['json']['routingPreference'] == 'TRAFFIC_AWARE_OPTIMAL'
        assert kwargs['headers']['X-Goog-Api-Key'] == 'test-secret'
        assert kwargs['allow_redirects'] is False
        assert client.post(PATH, json=ORIGIN).status_code == 429
        assert google.call_count == 1


@pytest.mark.parametrize('result,code', [
    (Mock(status_code=403), 'ROUTES_REJECTED'),
    (Mock(status_code=200, json=lambda: {'routes': []}), 'ROUTE_NOT_FOUND'),
    (Mock(status_code=200, json=lambda: {'routes': None}), 'ROUTES_UNAVAILABLE'),
])
def test_upstream_failures_are_safe(result, code):
    login()
    with patch('app.sos_routes.execute', return_value=CONFIRMED), patch('app.sos_routes.requests.post', return_value=result):
        assert client.post(PATH, json=ORIGIN).json()['detail']['code'] == code


def test_timeout_never_exposes_credentials():
    login()
    with patch('app.sos_routes.execute', return_value=CONFIRMED), patch('app.sos_routes.requests.post', side_effect=requests.Timeout('test-secret')):
        response = client.post(PATH, json=ORIGIN)
        assert response.status_code == 503
        assert 'test-secret' not in response.text


def test_route_follows_private_live_destination_not_recorded_incident():
    login()
    target={'latitude':-8.16,'longitude':-79.08,'live':True}
    with patch('app.sos_routes.execute', side_effect=[CONFIRMED,target]), patch('app.sos_routes.compute_route',return_value={}) as compute:
        assert client.post(PATH,json=ORIGIN).status_code==200
        assert compute.call_args.args[2]=={'latitude':-8.16,'longitude':-79.08}
