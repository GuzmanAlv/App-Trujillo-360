from uuid import uuid4
import psycopg
import pytest
from test_sos_cases_database import database

def test_waiting_hung_up_timeout_and_answered(database):
    citizen,operator=uuid4(),uuid4()
    with psycopg.connect(database) as c:
        for uid,role in [(citizen,'citizen'),(operator,'operator')]:
            c.execute("INSERT INTO trujillo.users(id,auth_provider,auth_subject,display_name,role) VALUES(%s,'firebase',%s,'Test',%s)",(uid,str(uid),role))
    def query(uid,sql,args=()):
        with psycopg.connect(database) as c:
            c.execute("SELECT set_config('app.firebase_uid',%s,true)",(str(uid),))
            c.execute('SET LOCAL ROLE trujillo_api')
            return c.execute(sql,args).fetchone()[0]
    case=query(citizen,'SELECT trujillo.submit_sos(%s,-8,-79)',(uuid4(),))['id']
    query(citizen,"SELECT trujillo.call_action(%s,'start')",(case,))
    def status():return query(operator,'SELECT trujillo.sos_map_call_status(%s)',(case,))
    def change(sql):
        with psycopg.connect(database) as c:c.execute(sql,(case,))
    assert status()['call_waiting'] is True
    assert status()['unanswered_alert'] is False
    with pytest.raises(psycopg.errors.InsufficientPrivilege):query(citizen,'SELECT trujillo.sos_map_call_status(%s)',(case,))
    change("UPDATE trujillo.call_sessions SET created_at=now()-interval '12 seconds' WHERE id=%s")
    assert status()['call_waiting'] is True and status()['unanswered_alert'] is True
    query(citizen,"SELECT trujillo.call_action(%s,'end')",(case,))
    assert status()['call_waiting'] is False and status()['unanswered_alert'] is True
    change("UPDATE trujillo.call_sessions SET created_at=now()-interval '60 seconds' WHERE id=%s")
    assert status()['unanswered_alert'] is True
    change("UPDATE trujillo.call_sessions SET created_at=now()-interval '4 seconds',ended_at=now() WHERE id=%s")
    assert status()['unanswered_alert'] is False
    change("UPDATE trujillo.call_sessions SET state='waiting',created_at=now()-interval '100 seconds',expires_at=now()-interval '10 seconds',ended_at=NULL WHERE id=%s")
    assert status()['call_waiting'] is False and status()['unanswered_alert'] is True
    assert status()['call_state']=='unanswered'
    change("UPDATE trujillo.call_sessions SET accepted_at=now()-interval '80 seconds',state='ended' WHERE id=%s")
    assert status()['unanswered_alert'] is False
