from uuid import uuid4
from unittest.mock import patch
import psycopg
from psycopg.types.json import Jsonb
from fastapi import FastAPI
from fastapi.testclient import TestClient
from app import citizen_sos
from app.auth import identity
from test_sos_cases_database import database

def test_pending_sos_visible_only_to_owner_then_transitions_without_duplicate(database):
    owner,other,operator=[uuid4() for _ in range(3)]
    with psycopg.connect(database) as c:
        for uid,role in [(owner,'citizen'),(other,'citizen'),(operator,'operator')]:
            c.execute("INSERT INTO trujillo.users(id,auth_provider,auth_subject,display_name,role) VALUES(%s,'firebase',%s,'Test',%s)",(uid,str(uid),role))
    def query(uid,sql,args=(),many=False):
        with psycopg.connect(database) as c:
            c.execute("SELECT set_config('app.firebase_uid',%s,true)",(str(uid),))
            c.execute('SET LOCAL ROLE trujillo_api')
            cur=c.execute(sql,args)
            return [r[0] for r in cur] if many else cur.fetchone()[0]
    case=query(owner,'SELECT trujillo.submit_sos(%s,-8.11,-79.03)',(uuid4(),))['id']
    query(owner,"SELECT trujillo.call_action(%s,'start')",(case,))
    with psycopg.connect(database) as c:c.execute("UPDATE trujillo.call_sessions SET expires_at=now()-interval '1 second' WHERE id=%s",(case,))
    query(owner,"SELECT trujillo.call_action(%s,'status')",(case,))
    rows=query(owner,'SELECT trujillo.citizen_sos_map_cases()',many=True)
    assert len(rows)==1 and rows[0]['id']==case and rows[0]['decision']=='pending'
    assert rows[0]['latitude']==-8.11 and rows[0]['longitude']==-79.03
    assert rows[0]['call_state']=='unanswered' and rows[0]['can_contribute'] is False
    assert rows[0]['incident_id'] is None
    assert query(owner,'SELECT trujillo.citizen_sos_cases()',many=True)==[] # Existing confirmed-only tracker unchanged.
    assert query(other,'SELECT trujillo.citizen_sos_map_cases()',many=True)==[]
    assert query(other,'SELECT trujillo.citizen_sos_map_cases(%s)',(case,),many=True)==[]
    assert query(other,'SELECT * FROM trujillo.map_incidents(-9,-7,-80,-78)',many=True)==[]
    data=dict(action='confirm',category='Robo',latitude=-8.12,longitude=-79.04,place='',public_description='',internal_note='PRIVATE',outcome='')
    confirmed=query(operator,'SELECT trujillo.sos_case_update(%s,%s,0,%s)',(case,uuid4(),Jsonb(data)))
    rows=query(owner,'SELECT trujillo.citizen_sos_map_cases()',many=True)
    assert len(rows)==1 and rows[0]['decision']=='confirmed' and rows[0]['latitude']==-8.12
    assert rows[0]['incident_id']==confirmed['incident_id'] and 'PRIVATE' not in str(rows)
    query(operator,'SELECT trujillo.sos_case_update(%s,%s,1,%s)',(case,uuid4(),Jsonb({**data,'action':'resolve','outcome':'Atención terminada'})))
    assert query(owner,'SELECT trujillo.citizen_sos_map_cases()',many=True)==[]
    assert query(owner,'SELECT trujillo.citizen_sos_map_cases(%s)',(case,))['attention']=='resolved'

def test_pending_map_static_route_is_authenticated_and_private():
    app=FastAPI()
    app.include_router(citizen_sos.router)
    with patch('app.citizen_sos.execute') as db:
        assert TestClient(app).get('/my-sos/map').status_code==401
        db.assert_not_called()
    app.dependency_overrides[identity]=lambda:{'sub':'owner'}
    with patch('app.citizen_sos.execute',return_value=[{'id':'pending','decision':'pending'}]) as db:
        response=TestClient(app).get('/my-sos/map')
        assert response.status_code==200 and response.headers['cache-control']=='private, no-store'
        assert db.call_args.args[1]=='SELECT trujillo.citizen_sos_map_cases()'
