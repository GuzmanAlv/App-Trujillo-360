from uuid import uuid4
import psycopg
import pytest
from psycopg.types.json import Jsonb
from test_sos_cases_database import database

def test_automatic_dispatch_and_arrival_quality_assignment_and_idempotency(database):
    citizen, operator, other = [uuid4() for _ in range(3)]
    with psycopg.connect(database) as c:
        for uid,role in [(citizen,'citizen'),(operator,'operator'),(other,'operator')]:
            c.execute("INSERT INTO trujillo.users(id,auth_provider,auth_subject,display_name,role) VALUES(%s,'firebase',%s,'Test',%s)",(uid,str(uid),role))
    def query(uid,sql,args=()):
        with psycopg.connect(database) as c:
            c.execute("SELECT set_config('app.firebase_uid',%s,true)",(str(uid),))
            c.execute('SET LOCAL ROLE trujillo_api')
            return c.execute(sql,args).fetchone()[0]
    case=query(citizen,'SELECT trujillo.submit_sos(%s,-8,-79)',(uuid4(),))['id']
    data=dict(action='confirm',category='Robo',latitude=-8.12,longitude=-79.04,place='',public_description='',internal_note='',outcome='')
    request=uuid4()
    def update(uid,version,body=data):
        return query(uid,'SELECT trujillo.sos_case_update(%s,%s,%s,%s)',(case,request if body is data else uuid4(),version,Jsonb(body)))
    confirmed=update(operator,0)
    assert confirmed['attention']=='en_route' and confirmed['can_track'] is True
    assert update(operator,0)['version']==1
    assert query(citizen,'SELECT trujillo.citizen_sos_cases()')['attention']=='en_route'
    def gps(uid=operator,lat=-8.12,lng=-79.04,accuracy=10,age=0):
        return query(uid,"SELECT trujillo.sos_arrival_check(%s,%s,%s,%s,clock_timestamp()-(%s * interval '1 second'))",(case,lat,lng,accuracy,age))
    with pytest.raises(psycopg.errors.InsufficientPrivilege):gps(other)
    with pytest.raises(psycopg.errors.InsufficientPrivilege):gps(citizen)
    with pytest.raises(psycopg.errors.InsufficientPrivilege):update(operator,1,{**data,'action':'on_scene'})
    assert gps(lat=-8,lng=-79)['reason']=='outside' # Phone origin is not incident destination.
    assert gps(accuracy=100)['reason']=='gps_quality'
    assert gps(age=50)['reason']=='gps_quality'
    assert gps()['reason']=='checking'
    assert gps()['attention']=='en_route' # One accurate reading alone is insufficient.
    assert gps(accuracy=100)['reason']=='gps_quality' # Resets debounce.
    assert gps()['reason']=='checking'
    with psycopg.connect(database) as c:
        c.execute("UPDATE trujillo.sos_arrival_samples SET first_at=clock_timestamp()-interval '12 seconds',observed_at=clock_timestamp()-interval '12 seconds' WHERE case_id=%s",(case,))
    assert gps()['attention']=='on_scene'
    assert gps()['attention']=='on_scene'
    result=query(operator,'SELECT trujillo.sos_case_read(%s)',(case,))
    assert result['version']==2 and len(result['events'])==2
    assert query(citizen,'SELECT trujillo.public_case_fields(%s::uuid[])',([result['incident_id']],))['attention']=='on_scene'
    resolved=update(operator,2,{**data,'action':'resolve','outcome':'Atención finalizada'})
    assert gps()['attention']=='resolved' and resolved['attention']=='resolved'
    with psycopg.connect(database) as c:
        c.execute('SET LOCAL ROLE trujillo_api')
        with pytest.raises(psycopg.errors.InsufficientPrivilege):c.execute('SELECT * FROM trujillo.sos_arrival_samples')
