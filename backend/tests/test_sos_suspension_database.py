from uuid import uuid4
import psycopg
import pytest
from psycopg.types.json import Jsonb
from test_sos_cases_database import database

def test_en_route_discard_and_suspension_are_authorized_atomic_and_idempotent(database):
    caller, plain_caller, operator, other, op_caller = [uuid4() for _ in range(5)]
    with psycopg.connect(database) as c:
        for uid,role in [(caller,'citizen'),(plain_caller,'citizen'),(operator,'operator'),(other,'operator'),(op_caller,'operator')]:
            c.execute("INSERT INTO trujillo.users(id,auth_provider,auth_subject,display_name,role) VALUES(%s,'firebase',%s,'Test',%s)",(uid,str(uid),role))
    def query(uid,sql,args=(),many=False):
        with psycopg.connect(database) as c:
            c.execute("SELECT set_config('app.firebase_uid',%s,true)",(str(uid),))
            c.execute('SET LOCAL ROLE trujillo_api')
            cur=c.execute(sql,args)
            return cur.fetchall() if many else cur.fetchone()[0]
    def new_case(citizen):
        case=query(citizen,'SELECT trujillo.submit_sos(%s,-8.11,-79.03)',(uuid4(),))['id']
        query(citizen,"SELECT trujillo.call_action(%s,'start')",(case,))
        query(operator,"SELECT trujillo.call_action(%s,'accept')",(case,))
        return case
    data=dict(action='confirm',category='Auxilio',latitude=-8.11,longitude=-79.03,place='',public_description='',internal_note='En camino al lugar',outcome='')
    def update(case,uid,version,body,request=None):
        return query(uid,'SELECT trujillo.sos_case_update(%s,%s,%s,%s)',(case,request or uuid4(),version,Jsonb(body)))
    case=new_case(plain_caller)
    confirmed=update(case,operator,0,data)
    assert confirmed['attention']=='en_route'
    discarded=update(case,operator,1,{**data,'action':'discard','internal_note':'El ciudadano confirma que fue una activación accidental.'})
    assert discarded['decision']=='discarded' and discarded['attention']=='resolved'
    assert query(operator,"SELECT trujillo.call_action(%s,'status')",(case,))['state']=='ended'
    assert query(plain_caller,'SELECT trujillo.push_preferences(%s)',(uuid4(),)) is None
    case=new_case(caller)
    confirmed=update(case,operator,0,data)
    blocked={**data,'action':'discard_block','internal_note':'Uso malicioso comprobado durante la llamada.'}
    with pytest.raises(psycopg.errors.InsufficientPrivilege):update(case,other,1,blocked)
    with pytest.raises(psycopg.errors.InsufficientPrivilege):update(case,caller,1,blocked)
    with pytest.raises(psycopg.errors.InvalidParameterValue):update(case,operator,1,{**blocked,'internal_note':''})
    assert query(caller,'SELECT trujillo.push_preferences(%s)',(uuid4(),)) is None
    request=uuid4()
    result=update(case,operator,1,blocked,request)
    assert result['decision']=='discarded' and result['incident_id']==confirmed['incident_id']
    assert len(result['events'])==2 and result['events'][0]['action']=='discard_block'
    assert update(case,operator,1,blocked,request)['version']==2
    assert query(plain_caller,'SELECT trujillo.public_case_fields(%s::uuid[])',([confirmed['incident_id']],),many=True)==[]
    with pytest.raises(psycopg.errors.InsufficientPrivilege):query(caller,'SELECT trujillo.push_preferences(%s)',(uuid4(),))
    with pytest.raises(psycopg.errors.InsufficientPrivilege):query(caller,'SELECT trujillo.submit_sos(%s,-8,-79)',(uuid4(),))
    with psycopg.connect(database) as c:
        row=c.execute('SELECT status,suspension_reason FROM trujillo.users WHERE id=%s',(caller,)).fetchone()
        assert row[0]=='suspended' and 'Uso malicioso' in row[1]
        assert c.execute('SELECT state FROM trujillo.call_sessions WHERE id=%s',(case,)).fetchone()[0]=='ended'
        assert c.execute('SELECT status FROM trujillo.users WHERE id=%s',(operator,)).fetchone()[0]=='active'
    case=new_case(op_caller)
    update(case,operator,0,data)
    with pytest.raises(psycopg.errors.InsufficientPrivilege):update(case,operator,1,blocked)
    assert query(op_caller,'SELECT trujillo.push_preferences(%s)',(uuid4(),)) is None
    assert query(operator,'SELECT trujillo.sos_case_read(%s)',(case,))['decision']=='confirmed'
