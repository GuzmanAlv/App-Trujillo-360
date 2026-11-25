from unittest.mock import patch
from uuid import uuid4
import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from app.main import app
from app.auth import identity
from app.workflows import execute
from app.sos_dispatch_worker import SosDispatchWorker
from app.push_worker import message

def test_handoff_requires_identity():
    with patch('app.sos_cases.execute') as db:
        assert TestClient(app).post(f'/operator/sos-cases/{uuid4()}/handoff').status_code==401
        db.assert_not_called()

def test_rate_limit_commits_and_returns_retry_after():
    with patch('app.workflows.connect') as connect:
        context=connect.return_value
        context.__enter__.return_value.execute.return_value.fetchone.return_value=[{'error_code':'SOS_RATE_LIMIT','retry_after':60}]
        with pytest.raises(HTTPException) as caught:
            execute({'sub':'caller'},'SELECT test()')
        assert caught.value.status_code==429 and caught.value.headers['Retry-After']=='60'
        assert context.__exit__.call_args.args==(None,None,None)

def test_handoff_private_and_availability_role_denial():
    app.dependency_overrides[identity]=lambda:{'sub':'test'}
    try:
        with patch('app.sos_cases.execute',return_value={'transferring':True}) as db:
            response=TestClient(app).post(f'/operator/sos-cases/{uuid4()}/handoff')
            assert response.status_code==200 and response.headers['cache-control']=='private, no-store'
            assert 'operator_handoff' in db.call_args.args[1]
        with patch('app.sos_cases.execute',side_effect=HTTPException(403)):
            assert TestClient(app).post('/operator/availability/heartbeat').status_code==403
    finally:app.dependency_overrides.clear()

def test_dispatch_clock_runs_without_push_configuration():
    worker=SosDispatchWorker()
    with patch('app.sos_dispatch_worker.dispatch_once',side_effect=lambda:worker.stop.set()) as tick:
        worker.run()
        tick.assert_called_once()

def test_assignment_push_can_open_the_operator_map_without_private_gps():
    payload=message(dict(token='test',kind='operator',target_id='case',account_uid='uid',job_id='event',
        title='Transferencia',body='Acepta el caso',assignment_offer=True,quiet=False))['message']
    assert payload['data']['assignment_offer']=='true'
    assert 'latitude' not in payload['data']
