from unittest.mock import patch
from uuid import uuid4
import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.auth import identity

client=TestClient(app)
CASE=str(uuid4())

@pytest.mark.parametrize('method,path', [('get','/operator/calls/incoming'),('get',f'/operator/sos-cases/{CASE}'),('post',f'/operator/sos-cases/{CASE}')])
def test_identity_required(method,path):
    with patch('app.sos_cases.execute') as db:
        assert getattr(client,method)(path).status_code==401
        db.assert_not_called()

def test_validation_and_private_response():
    app.dependency_overrides[identity]=lambda:{'sub':'operator'}
    data=dict(request_id=str(uuid4()),version=0,action='confirm',category='Robo',latitude=-8,longitude=-79,
              place='Lugar',public_description='Público',internal_note='Privado')
    try:
        with patch('app.sos_cases.execute',return_value={'id':CASE,'decision':'confirmed'}) as db:
            for invalid in [{'latitude':91},{'role':'admin'},{'action':'publish'}, {'version':-1}, {'arrival_position':{'latitude':0,'longitude':0,'accuracy':-1}}]:
                assert client.post(f'/operator/sos-cases/{CASE}',json={**data,**invalid}).status_code==422
            db.assert_not_called()
            response=client.post(f'/operator/sos-cases/{CASE}',json=data)
            assert response.status_code==200
            assert response.headers['cache-control']=='private, no-store'
            assert db.call_args.args[2][3].obj['internal_note']=='Privado'
    finally:
        app.dependency_overrides.clear()
