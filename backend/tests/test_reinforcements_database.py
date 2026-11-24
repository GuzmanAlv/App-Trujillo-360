from uuid import uuid4
import psycopg
import pytest
from psycopg.types.json import Jsonb
from test_sos_cases_database import database, arrive

def test_private_reinforcements_priority_and_on_scene_false_alarm(database):
    citizen, requester, operator = [uuid4() for _ in range(3)]
    with psycopg.connect(database) as c:
        for uid,role in [(citizen,'citizen'),(requester,'operator'),(operator,'operator')]:
            c.execute("INSERT INTO trujillo.users(id,auth_provider,auth_subject,display_name,role) VALUES(%s,'firebase',%s,'Test',%s)",(uid,str(uid),role))
    def query(uid,sql,args=(),many=False):
        with psycopg.connect(database) as c:
            c.execute("SELECT set_config('app.firebase_uid',%s,true)",(str(uid),))
            c.execute('SET LOCAL ROLE trujillo_api')
            cur=c.execute(sql,args)
            return cur.fetchall() if many else cur.fetchone()[0]
    query(operator,"SELECT trujillo.operator_position(-8.12,-79.04,10,clock_timestamp())")
    query(operator,'SELECT trujillo.push_register(%s,%s,false,true,NULL,NULL,500,false)',(uuid4(),'operator-token-'+str(uuid4())))
    request_id=uuid4()
    def request(user=requester,rid=request_id):
        return query(user,'SELECT trujillo.reinforcement_request(%s,-8.12,-79.04,15,clock_timestamp())',(rid,))
    with pytest.raises(psycopg.errors.InsufficientPrivilege):request(citizen)
    own=request()
    assert own['is_mine'] is True
    assert request()['id']==own['id']
    assert request(rid=uuid4())['id']==own['id'] # One active request per operator.
    with pytest.raises(psycopg.errors.InsufficientPrivilege):query(citizen,'SELECT trujillo.reinforcement_list()',many=True)
    with pytest.raises(psycopg.errors.InsufficientPrivilege):query(operator,'SELECT trujillo.reinforcement_close(%s)',(own['id'],))
    with pytest.raises(psycopg.errors.InsufficientPrivilege):request(operator)
    with pytest.raises(psycopg.errors.InsufficientPrivilege):query(requester,'SELECT trujillo.reinforcement_destination(%s)',(own['id'],))
    with psycopg.connect(database) as c:
        c.execute('SET LOCAL ROLE trujillo_api')
        job=c.execute('SELECT trujillo.push_claim()').fetchone()[0]
        assert job['kind']=='reinforcement' and job['quiet'] is True
        assert job['account_uid']==str(operator) and 'latitude' not in job
        c.execute("SELECT trujillo.push_finish(%s,%s,'sent')",(job['job_id'],job['lease']))
    destination=query(operator,'SELECT trujillo.reinforcement_destination(%s)',(own['id'],))
    assert destination['latitude']==-8.12 and destination['is_mine'] is False
    case=query(citizen,'SELECT trujillo.submit_sos(%s,-8.11,-79.03)',(uuid4(),))['id']
    data=dict(action='confirm',category='Robo',latitude=-8.11,longitude=-79.03,place='',public_description='',internal_note='Motivo privado',outcome='')
    def update(version,body):
        return query(operator,'SELECT trujillo.sos_case_update(%s,%s,%s,%s)',(case,uuid4(),version,Jsonb(body)))
    confirmed=update(0,data)
    with pytest.raises(psycopg.errors.RaiseException):query(operator,'SELECT trujillo.reinforcement_destination(%s)',(own['id'],))
    with pytest.raises(psycopg.errors.InvalidParameterValue):update(1,{**data,'action':'discard','internal_note':''})
    arrive(database,query,operator,case,-8.11,-79.03)
    assert query(operator,'SELECT trujillo.reinforcement_destination(%s)',(own['id'],))['id']==own['id']
    with pytest.raises(psycopg.errors.InvalidParameterValue):update(2,{**data,'action':'discard','internal_note':''})
    discarded=update(2,{**data,'action':'discard','internal_note':'Se comprobó falsa alarma en el lugar.'})
    assert discarded['decision']=='discarded' and discarded['attention']=='resolved'
    assert discarded['incident_id']==confirmed['incident_id']
    assert query(citizen,'SELECT trujillo.public_case_fields(%s::uuid[])',([confirmed['incident_id']],),many=True)==[]
    assert len(discarded['events'])==3
    with psycopg.connect(database) as c:
        assert c.execute('SELECT status FROM trujillo.incidents WHERE id=%s',(confirmed['incident_id'],)).fetchone()[0]=='discarded'
        assert c.execute('SELECT count(*) FROM trujillo.reinforcements WHERE operator_id=%s',(requester,)).fetchone()[0]==1
    with pytest.raises(psycopg.errors.InvalidParameterValue):query(requester,"SELECT trujillo.reinforcement_position(%s,-8,-79,15,clock_timestamp()-interval '2 minutes')",(own['id'],))
    query(requester,'SELECT trujillo.reinforcement_position(%s,-8.13,-79.05,15,clock_timestamp())',(own['id'],))
    assert query(operator,'SELECT trujillo.reinforcement_destination(%s)',(own['id'],))['latitude']==-8.13
    query(requester,'SELECT trujillo.reinforcement_close(%s)',(own['id'],))
    assert query(operator,'SELECT trujillo.reinforcement_list()',many=True)==[]
    with pytest.raises(psycopg.errors.NoDataFound):query(operator,'SELECT trujillo.reinforcement_destination(%s)',(own['id'],))
    request(rid=uuid4())
    new_sos=query(citizen,'SELECT trujillo.submit_sos(%s,-8.11,-79.03)',(uuid4(),))['id']
    with psycopg.connect(database) as c:
        c.execute('SET LOCAL ROLE trujillo_api')
        job=c.execute('SELECT trujillo.push_claim()').fetchone()[0]
        while job and job.get('skipped'):
            job=c.execute('SELECT trujillo.push_claim()').fetchone()[0]
        assert job['kind']=='operator' and job['target_id']==new_sos # Citizen SOS before an older reinforcement job.
    with psycopg.connect(database) as c:
        c.execute('SET LOCAL ROLE trujillo_api')
        with pytest.raises(psycopg.errors.InsufficientPrivilege):c.execute('SELECT * FROM trujillo.reinforcements')
