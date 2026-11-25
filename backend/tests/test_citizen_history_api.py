from fastapi import FastAPI
from fastapi.testclient import TestClient
from app import citizen_sos
from app.auth import identity


def test_history_static_route_is_owner_authenticated_and_paginates(monkeypatch):
    app=FastAPI()
    app.include_router(citizen_sos.router)
    app.dependency_overrides[identity]=lambda:{'sub':'owner'}
    seen=[]
    def execute(claims,sql,args=(),many=False):
        seen.append((claims,sql,args,many))
        return [{'id':'old-closed','attention':'resolved'}]
    monkeypatch.setattr(citizen_sos,'execute',execute)
    with TestClient(app) as client:
        response=client.get('/my-sos/history?limit=50&offset=50')
        assert response.status_code==200 and response.json()[0]['attention']=='resolved'
        assert response.headers['cache-control']=='private, no-store'
        assert seen[0]==({'sub':'owner'},'SELECT trujillo.citizen_sos_history(%s,%s)',(50,50),True)
        for query in ('limit=101','offset=-1','limit=0'):
            assert client.get('/my-sos/history?'+query).status_code==422
        assert len(seen)==1


def test_nearby_sos_route_uses_fixed_server_radius(monkeypatch):
    app=FastAPI()
    app.include_router(citizen_sos.router)
    app.dependency_overrides[identity]=lambda:{'sub':'owner'}
    seen=[]
    def execute(claims,sql,args=(),many=False):
        seen.append((claims,sql,args,many))
        return [{'id':'confirmed','is_sos':True}]
    monkeypatch.setattr(citizen_sos,'execute',execute)
    with TestClient(app) as client:
        response=client.get('/incidents/nearby-sos?latitude=-8.1&longitude=-79')
        assert response.status_code==200 and response.json()[0]['is_sos'] is True
        assert response.headers['cache-control']=='private, no-store'
        assert seen[0]==({'sub':'owner'},'SELECT trujillo.nearby_sos(%s,%s)',(-8.1,-79),True)
        assert client.get('/incidents/nearby-sos?latitude=91&longitude=-79').status_code==422
        assert len(seen)==1
