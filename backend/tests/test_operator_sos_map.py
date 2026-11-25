from unittest.mock import patch
from uuid import uuid4
import psycopg
import pytest
from fastapi import Response
from fastapi.testclient import TestClient
from psycopg.types.json import Jsonb
from app.main import app
from app.sos_cases import map_cases
from test_sos_cases_database import database

def test_map_requires_identity():
    with patch('app.sos_cases.execute') as execute:
        assert TestClient(app).get('/operator/sos-map').status_code==401
        execute.assert_not_called()

def test_private_map_permissions_location_and_closed_cases(database):
    with patch('app.sos_cases.execute',return_value=[]) as execute:
        response=Response()
        map_cases(response,{'sub':'test'})
        sql=execute.call_args.args[1]
        assert response.headers['cache-control']=='private, no-store'
    citizen,operator=uuid4(),uuid4()
    with psycopg.connect(database) as c:
        for uid,role in [(citizen,'citizen'),(operator,'operator')]:
            c.execute("INSERT INTO trujillo.users(id,auth_provider,auth_subject,display_name,role) VALUES(%s,'firebase',%s,'Test',%s)",(uid,str(uid),role))
    def query(uid,statement,args=(),many=False):
        with psycopg.connect(database) as c:
            c.execute("SELECT set_config('app.firebase_uid',%s,true)",(str(uid),))
            c.execute('SET LOCAL ROLE trujillo_api')
            cursor=c.execute(statement,args)
            return cursor.fetchall() if many else cursor.fetchone()[0]
    case=query(citizen,'SELECT trujillo.submit_sos(%s,-8,-79)',(uuid4(),))['id']
    query(citizen,"SELECT trujillo.submit_help(%s,'Auxilio','Solo ayuda','Privado',-8,-79,'Alta')",(uuid4(),))
    with pytest.raises(psycopg.errors.InsufficientPrivilege):query(citizen,sql,many=True)
    rows=[r[0] for r in query(operator,sql,many=True)]
    marker=next(r for r in rows if r['id']==case)
    assert marker['decision']=='pending' and marker['latitude']==-8
    assert set(marker)=={'id','latitude','longitude','decision','attention','support_requested','incident_id','call_state','call_waiting','unanswered_alert','category','can_track','available','claimed_by_me','received_at','alert_in_range','assignment_state','assignment_offer','operator_name','offer_expires_at','escalation_level'}
    assert marker['available'] is True
    payload=dict(action='support',category='Robo',latitude=-8.12,longitude=-79.04,
                 place='',public_description='',internal_note='Solo para el operador',outcome='')
    query(operator,'SELECT trujillo.sos_case_update(%s,%s,0,%s)',(case,uuid4(),Jsonb(payload)))
    rows=[r[0] for r in query(operator,sql,many=True)]
    marker=next(r for r in rows if r['id']==case)
    assert marker['latitude']==-8.12 and marker['support_requested'] is True
    assert 'Solo para el operador' not in str(rows)
    query(operator,'SELECT trujillo.sos_case_update(%s,%s,1,%s)',(case,uuid4(),Jsonb({**payload,'action':'discard'})))
    assert not any(r[0]['id']==case for r in query(operator,sql,many=True))
