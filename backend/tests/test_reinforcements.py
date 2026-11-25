from unittest.mock import patch
from uuid import uuid4
import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from app.main import app
from app.auth import identity

client=TestClient(app)
ID=str(uuid4())
PATH='/operator/reinforcements'

def test_requires_identity_and_does_not_call_database():
    with patch('app.reinforcements.execute') as db:
        assert client.get(PATH).status_code==401
        db.assert_not_called()

def test_validates_location_and_enforces_sos_before_google_request():
    app.dependency_overrides[identity]=lambda:{'sub':'operator'}
    try:
        with patch('app.reinforcements.execute') as db:
            assert client.post(PATH,json={'request_id':ID,'latitude':0,'longitude':0,'accuracy':200,'observed_at':'2026-11-19T12:00:00Z'}).status_code==422
            assert client.post(PATH+'/'+ID+'/route',json={'latitude':0,'longitude':0,'destination':{'latitude':0}}).status_code==422
            db.assert_not_called()
        with patch('app.reinforcements.execute',side_effect=HTTPException(409)), patch('app.reinforcements.compute_route') as google:
            r=client.post(PATH+'/'+ID+'/route',json={'latitude':0,'longitude':0})
            assert r.status_code==409 and r.json()['detail']['code']=='SOS_PRIORITY'
            google.assert_not_called()
        with patch('app.reinforcements.execute',return_value={'latitude':-8.12,'longitude':-79.04}), patch('app.reinforcements.compute_route',return_value={'encoded_polyline':'test'}) as google:
            r=client.post(PATH+'/'+ID+'/route',json={'latitude':-8.11,'longitude':-79.03})
            assert r.status_code==200 and r.headers['cache-control']=='private, no-store'
            assert google.call_args.args[2]=={'latitude':-8.12,'longitude':-79.04}
    finally:app.dependency_overrides.clear()
