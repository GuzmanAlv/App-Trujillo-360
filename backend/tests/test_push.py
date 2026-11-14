from unittest.mock import patch
from uuid import uuid4
import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.auth import identity
from app.push_worker import message, outcome, configured

@pytest.fixture
def client():
    app.dependency_overrides[identity]=lambda:{'sub':'test'}
    yield TestClient(app)
    app.dependency_overrides.clear()

@pytest.mark.parametrize('data',[
    {'token':'x'*30,'citizen_enabled':True},
    {'token':'short'},
    {'token':'x'*30,'latitude':91},
    {'token':'x'*30,'radius':99999},
    {'token':'x'*30,'user_id':str(uuid4())},
])
def test_invalid_registration_does_not_reach_database(client,data):
    with patch('app.workflows.connect') as database:
        assert client.put('/push/devices/'+str(uuid4()),json=data).status_code==422
        database.assert_not_called()

def test_registration_has_private_response(client):
    data={'token':'x'*30,'operator_enabled':True}
    with patch('app.push.execute',return_value={'operator_enabled':True}) as execute, patch('app.push.configured',return_value=False):
        response=client.put('/push/devices/'+str(uuid4()),json=data)
        assert response.status_code==200
        assert 'token' not in response.text
        assert response.json()['sender_configured'] is False
        assert response.headers['cache-control']=='private, no-store'
        assert execute.call_args.args[2][3] is True

def test_payload_does_not_include_private_case_details():
    payload=message(dict(token='test',kind='operator',target_id='target',account_uid='uid',job_id='event',title='Nuevo reporte',body='Revisar',description='private',latitude=1))['message']
    assert payload['notification']['title']=='Nuevo reporte'
    assert 'latitude' not in payload['data'] and 'description' not in payload['data']
    assert payload['android']['notification']['tag']=='event'

def test_citizen_alert_uses_incident_category_without_claiming_live_distance():
    payload=message(dict(token='test',kind='citizen',target_id='target',account_uid='uid',job_id='event',title='Incidente confirmado en tu zona',body='Robo. Toca para consultar el detalle.'))['message']
    assert payload['notification']['title']=='🚨 Alerta: Robo en tu zona'
    assert 'zona configurada' in payload['notification']['body']
    assert payload['android']['notification']['color']=='#D32F2F'

def test_invalid_token_and_auth_failure_differ():
    from unittest.mock import Mock
    assert outcome(Mock(status_code=403,json=lambda:{}))=='retry'
    assert outcome(Mock(status_code=404,json=lambda:{'error':{'details':[{'errorCode':'UNREGISTERED'}]}}))=='unregistered'
    assert outcome(Mock(status_code=200))=='sent'
    assert outcome(Mock(status_code=429,json=lambda:{}))=='retry'

def test_sender_stays_off_without_explicit_configuration():
    with patch('app.push_worker.settings',return_value={}):
        assert configured() is False
