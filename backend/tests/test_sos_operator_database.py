from uuid import uuid4
import psycopg
import pytest
from psycopg.types.json import Jsonb
from test_sos_cases_database import database

def test_optional_public_fields_support_and_return_call_consent(database):
    citizen,operator,outsider=[uuid4() for _ in range(3)]
    with psycopg.connect(database) as c:
        for uid,role in [(citizen,'citizen'),(operator,'operator'),(outsider,'operator')]:
            c.execute("INSERT INTO trujillo.users(id,auth_provider,auth_subject,display_name,role) VALUES(%s,'firebase',%s,'Test',%s)",(uid,str(uid),role))
    def query(uid,sql,args=(),many=False):
        with psycopg.connect(database) as c:
            c.execute("SELECT set_config('app.firebase_uid',%s,true)",(str(uid),))
            c.execute('SET LOCAL ROLE trujillo_api')
            cur=c.execute(sql,args)
            return cur.fetchall() if many else cur.fetchone()[0]
    case=query(citizen,'SELECT trujillo.submit_sos(%s,-8,-79)',(uuid4(),))['id']
    def call(uid,action):return query(uid,'SELECT trujillo.call_action(%s,%s)',(case,action))
    first=call(citizen,'start')
    call(operator,'accept')
    call(citizen,'end')
    data=dict(action='confirm',category='Auxilio',latitude=-8,longitude=-79,place='',public_description='',internal_note='',outcome='')
    result=query(operator,'SELECT trujillo.sos_case_update(%s,%s,0,%s)',(case,uuid4(),Jsonb(data)))
    assert result['decision']=='confirmed'
    for action,version in [('support',1),('support_clear',2)]:
        result=query(operator,'SELECT trujillo.sos_case_update(%s,%s,%s,%s)',(case,uuid4(),version,Jsonb({**data,'action':action})))
        assert result['support_requested']==(action=='support')
        rows=query(operator,'SELECT trujillo.list_help(true)',many=True)
        assert next(r[0] for r in rows if r[0]['id']==case)['sos_case']['support_requested']==(action=='support')
    with pytest.raises(psycopg.errors.InsufficientPrivilege):call(outsider,'callback')
    returning=call(operator,'callback')
    assert returning['state']=='waiting' and returning['room']!=first['room']
    assert call(operator,'callback')['room']==returning['room']
    assert query(outsider,'SELECT trujillo.incoming_calls()',many=True)==[]
    assert query(citizen,'SELECT trujillo.return_calls()')['callback'] is True
    with pytest.raises(psycopg.errors.InsufficientPrivilege):call(operator,'token')
    with pytest.raises(psycopg.errors.InsufficientPrivilege):call(outsider,'answer')
    call(citizen,'answer')
    assert call(operator,'token')['room']==returning['room']
    assert call(citizen,'token')['room']==returning['room']
    call(operator,'end')
    assert call(operator,'callback')['error_code']=='SOS_RATE_LIMIT'
    with psycopg.connect(database) as c:c.execute("UPDATE trujillo.sos_rate_events SET created_at=now()-interval '20 seconds' WHERE actor_id=%s",(operator,))
    assert call(operator,'callback')['room']!=returning['room']
