from uuid import uuid4
import psycopg
import pytest
from psycopg.types.json import Jsonb
from test_sos_cases_database import database, arrive

def test_sos_notices_are_private_deduplicated_and_quiet_for_busy_operator(database):
    citizen, other, operator = [uuid4() for _ in range(3)]
    citizen_device, op_device = uuid4(), uuid4()
    with psycopg.connect(database) as c:
        for uid,role in [(citizen,'citizen'),(other,'citizen'),(operator,'operator')]:
            c.execute("INSERT INTO trujillo.users(id,auth_provider,auth_subject,display_name,role) VALUES(%s,'firebase',%s,'Test',%s)",(uid,str(uid),role))
    def query(uid,sql,args=()):
        with psycopg.connect(database) as c:
            c.execute("SELECT set_config('app.firebase_uid',%s,true)",(str(uid),))
            c.execute('SET LOCAL ROLE trujillo_api')
            return c.execute(sql,args).fetchone()[0]
    query(citizen,'SELECT trujillo.push_register_sos(%s,%s)',(citizen_device,'citizen-token-'+str(uuid4())))
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        query(other,'SELECT trujillo.push_register_sos(%s,%s)',(citizen_device,'attacker-token-'+str(uuid4())))
    query(operator,"SELECT trujillo.operator_position(-8.12,-79.04,10,clock_timestamp())")
    query(operator,'SELECT trujillo.push_register(%s,%s,false,true,NULL,NULL,500,false)',(op_device,'operator-token-'+str(uuid4())))
    def claim():
        with psycopg.connect(database) as c:
            c.execute('SET LOCAL ROLE trujillo_api')
            job=c.execute('SELECT trujillo.push_claim()').fetchone()[0]
            if job and not job.get('skipped'):
                c.execute("SELECT trujillo.push_finish(%s,%s,'sent')",(job['job_id'],job['lease']))
            return job
    case=query(citizen,'SELECT trujillo.submit_sos(%s,-8.12,-79.04)',(uuid4(),))['id']
    assert claim()['quiet'] is False
    query(citizen,"SELECT trujillo.call_action(%s,'start')",(case,))
    query(operator,"SELECT trujillo.call_action(%s,'accept')",(case,))
    query(operator,"SELECT trujillo.call_action(%s,'end')",(case,))
    data=dict(action='confirm',category='Auxilio',latitude=-8.12,longitude=-79.04,place='',public_description='',internal_note='Privado',outcome='')
    query(operator,'SELECT trujillo.sos_case_update(%s,%s,0,%s)',(case,uuid4(),Jsonb(data)))
    query(other,'SELECT trujillo.submit_sos(%s,-8.13,-79.05)',(uuid4(),))
    quiet=claim()
    assert quiet['kind']=='operator' and quiet['quiet'] is True
    query(operator,"SELECT trujillo.call_action(%s,'callback')",(case,))
    query(operator,"SELECT trujillo.call_action(%s,'callback')",(case,))
    callback=claim()
    assert callback['kind']=='sos_callback' and callback['account_uid']==str(citizen)
    assert callback['target_id']==case and 'Privado' not in str(callback)
    assert claim() is None
    # Stale callbacks must not ring after the citizen answers.
    query(citizen,"SELECT trujillo.call_action(%s,'answer')",(case,))
    query(operator,"SELECT trujillo.call_action(%s,'end')",(case,))
    query(operator,"SELECT trujillo.call_action(%s,'callback')",(case,))
    query(citizen,"SELECT trujillo.call_action(%s,'answer')",(case,))
    assert claim()['skipped'] is True
    query(operator,"SELECT trujillo.call_action(%s,'end')",(case,))
    arrive(database,query,operator,case,-8.12,-79.04)
    notice=claim()
    assert notice['kind']=='sos_arrival' and notice['account_uid']==str(citizen)
    assert 'latitude' not in notice and 'Privado' not in str(notice)
    assert claim() is None
    own=query(citizen,'SELECT trujillo.citizen_sos_cases(%s)',(case,))
    assert own['arrived_at'] is not None
    with psycopg.connect(database) as c:
        assert c.execute("SELECT count(*) FROM trujillo.push_outbox WHERE kind='sos_arrival' AND target_id=%s",(case,)).fetchone()[0]==1
        assert c.execute('SELECT citizen_enabled FROM trujillo.push_devices WHERE id=%s',(citizen_device,)).fetchone()[0] is False
