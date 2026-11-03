from unittest.mock import patch
from uuid import uuid4
import psycopg
import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.auth import identity

client=TestClient(app)

@pytest.mark.parametrize('method,path',[
 ('get','/help-requests'),('post','/help-requests'),('get','/operator/help-requests'),
 ('get','/operator/incidents'),('post',f'/operator/incidents/{uuid4()}/decisions'),
 ('get','/incidents/density?south=0&north=1&west=0&east=1')])
def test_workflows_require_identity(method,path):
    with patch('app.workflows.connect') as db:
        assert getattr(client,method)(path).status_code==401
        db.assert_not_called()

@pytest.fixture
def signed():
    app.dependency_overrides[identity]=lambda:{'sub':'citizen'}
    yield
    app.dependency_overrides.clear()

def test_help_never_accepts_role_or_invalid_priority(signed):
    data=dict(request_id=str(uuid4()),category='Robo',place='Prueba',description='',latitude=-8.1,longitude=-79,priority='Alta')
    with patch('app.workflows.connect') as db:
        assert client.post('/help-requests',json={**data,'role':'operator'}).status_code==422
        assert client.post('/help-requests',json={**data,'priority':'inmediata'}).status_code==422
        db.assert_not_called()

def test_operator_denial_is_redacted(signed):
    with patch('app.workflows.connect',side_effect=psycopg.errors.InsufficientPrivilege('private')):
        response=client.get('/operator/help-requests')
    assert response.status_code==403 and 'private' not in response.text

def test_no_future_empty_reason_or_invalid_area_reaches_database(signed):
    with patch('app.workflows.connect') as db:
        assert client.post(f'/operator/help-requests/{uuid4()}/decisions',json={'stage':'Cerrada','priority':'Alta','reason':'  '}).status_code==422
        assert client.get('/incidents/density?south=20&north=10&west=0&east=1').status_code==422
        assert client.get('/incidents/density?south=0&north=1&west=0&east=1&hour_band=4').status_code==422
        db.assert_not_called()
