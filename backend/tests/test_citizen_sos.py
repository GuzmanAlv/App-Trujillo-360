from uuid import uuid4
from unittest.mock import patch
from fastapi.testclient import TestClient
import pytest
from app.main import app
from app.auth import identity

client=TestClient(app)
CASE=str(uuid4())

@pytest.mark.parametrize('method,path',[
 ('get','/my-sos'),('get',f'/my-sos/{CASE}'),('get',f'/sos-cases/{CASE}/contributions'),
 ('post',f'/my-sos/{CASE}/contributions'),('get',f'/sos-cases/{CASE}/photos/{uuid4()}')])
def test_identity_required(method,path):
    with patch('app.citizen_sos.execute') as db:
        assert getattr(client,method)(path).status_code==401
        db.assert_not_called()

def test_invalid_photo_and_owner_fields_rejected():
    app.dependency_overrides[identity]=lambda:{'sub':'citizen'}
    try:
        with patch('app.citizen_sos.execute') as db:
            assert client.post(f'/my-sos/{CASE}/contributions',json={'request_id':str(uuid4()),'user_id':str(uuid4())}).status_code==422
            assert client.post(f'/my-sos/{CASE}/contributions',json={'request_id':str(uuid4()),'photos':[{'id':str(uuid4()),'content_base64':'AAAA'}]}).status_code==422
            db.assert_not_called()
    finally:app.dependency_overrides.clear()
