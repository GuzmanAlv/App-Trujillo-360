from uuid import uuid4
from concurrent.futures import ThreadPoolExecutor
import psycopg
import pytest
from psycopg.types.json import Jsonb
from test_sos_cases_database import database

def query(database,user,sql,args=(),many=False):
    with psycopg.connect(database) as c:
        if user:c.execute("SELECT set_config('app.firebase_uid',%s,true)",(str(user),))
        c.execute('SET LOCAL ROLE trujillo_api')
        cur=c.execute(sql,args)
        return [r[0] for r in cur] if many else cur.fetchone()[0]

def users(database,*roles):
    ids=[uuid4() for _ in roles]
    with psycopg.connect(database) as c:
        for uid,role in zip(ids,roles):
            c.execute("INSERT INTO trujillo.users(id,auth_provider,auth_subject,display_name,role) VALUES(%s,'firebase',%s,'Test',%s)",(uid,str(uid),role))
    return ids

def confirm(database,op,case):
    data=dict(action='confirm',category='Auxilio',latitude=-8.11,longitude=-79.03,place='',public_description='',internal_note='Private note',outcome='')
    return query(database,op,'SELECT trujillo.sos_case_update(%s,%s,0,%s)',(case,uuid4(),Jsonb(data)))

def test_one_pending_sos_and_rate_limits_keep_idempotent_retries(database):
    citizen,=users(database,'citizen')
    submit=lambda request:query(database,citizen,'SELECT trujillo.submit_sos(%s,-8.11,-79.03)',(request,))
    request=uuid4();first=submit(request)
    with ThreadPoolExecutor(max_workers=4) as pool:rows=list(pool.map(submit,[uuid4() for _ in range(8)]))
    assert all(r['id']==first['id'] and r['existing_active'] for r in rows)
    assert submit(request)['id']==first['id']
    for _ in range(2):
        with psycopg.connect(database) as c:c.execute("UPDATE trujillo.help_requests SET stage='Cerrada' WHERE id=%s",(first['id'],))
        first=submit(uuid4())
    with psycopg.connect(database) as c:c.execute("UPDATE trujillo.help_requests SET stage='Cerrada' WHERE id=%s",(first['id'],))
    assert submit(uuid4())['error_code']=='SOS_RATE_LIMIT'
    assert submit(request)['id']!=first['id'] # Original request still retrieves its receipt.
    caller,=users(database,'citizen')
    case=query(database,caller,'SELECT trujillo.submit_sos(%s,-8.11,-79.03)',(uuid4(),))['id']
    start=query(database,caller,"SELECT trujillo.call_action(%s,'start')",(case,))
    assert query(database,caller,"SELECT trujillo.call_action(%s,'start')",(case,))['room']==start['room']
    query(database,caller,"SELECT trujillo.call_action(%s,'end')",(case,))
    assert query(database,caller,'SELECT trujillo.citizen_call_operator(%s)',(case,))['error_code']=='SOS_RATE_LIMIT'

def test_unanswered_sos_expands_zones_on_server_clock(database):
    citizen,near,far=users(database,'citizen','operator','operator')
    query(database,near,'SELECT trujillo.operator_position(-8.11,-79.03,10,clock_timestamp())')
    query(database,far,'SELECT trujillo.operator_position(-8.33,-79.03,10,clock_timestamp())')
    for op in (near,far):query(database,op,'SELECT trujillo.push_register(%s,%s,false,true,NULL,NULL,500,false)',(uuid4(),'dispatch-'+str(uuid4())))
    case=query(database,citizen,'SELECT trujillo.submit_sos(%s,-8.11,-79.03)',(uuid4(),))['id']
    get=lambda:next(r for r in query(database,far,'SELECT trujillo.operator_sos_map_data()',many=True) if r['id']==case)
    assert get()['alert_in_range'] is False
    for age,level in [(31,1),(61,2),(121,3)]:
        with psycopg.connect(database) as c:c.execute("UPDATE trujillo.help_requests SET received_at=now()-make_interval(secs=>%s) WHERE id=%s",(age,case))
        query(database,None,'SELECT trujillo.sos_dispatch_tick()')
        assert get()['escalation_level']==level and get()['alert_in_range'] is True
    with psycopg.connect(database) as c:
        assert c.execute("SELECT count(*) FROM trujillo.push_outbox WHERE target_id=%s AND event_key LIKE 'escalation:%%'",(case,)).fetchone()[0]==6
    query(database,None,'SELECT trujillo.sos_dispatch_tick()') # No duplicate notifications per level/device.
    with pytest.raises(psycopg.errors.InsufficientPrivilege):query(database,citizen,'SELECT trujillo.operator_heartbeat(true)')

def test_offline_owner_transfers_to_nearest_free_operator_and_preserves_case(database):
    with psycopg.connect(database) as c:c.execute('UPDATE trujillo.operator_availability SET online=false')
    citizen,other_citizen,old,near,far,busy=users(database,'citizen','citizen','operator','operator','operator','operator')
    for op,lat in [(old,-8.11),(near,-8.112),(far,-8.20),(busy,-8.1101)]:
        query(database,op,'SELECT trujillo.operator_begin_duty()')
        query(database,op,'SELECT trujillo.operator_position(%s,-79.03,10,clock_timestamp())',(lat,))
    busy_case=query(database,other_citizen,'SELECT trujillo.submit_sos(%s,-8.11,-79.03)',(uuid4(),))['id']
    confirm(database,busy,busy_case)
    case=query(database,citizen,'SELECT trujillo.submit_sos(%s,-8.11,-79.03)',(uuid4(),))['id']
    query(database,citizen,"SELECT trujillo.call_action(%s,'start')",(case,))
    audio=query(database,old,"SELECT trujillo.call_action(%s,'accept')",(case,))
    original=confirm(database,old,case)
    with psycopg.connect(database) as c:
        c.execute("UPDATE trujillo.operator_availability SET last_seen=now()-interval '121 seconds' WHERE user_id=%s",(old,))
        c.execute("UPDATE trujillo.sos_rate_events SET created_at=now()-interval '20 seconds' WHERE actor_id=%s",(citizen,))
    query(database,None,'SELECT trujillo.sos_dispatch_tick()')
    offered=query(database,near,'SELECT trujillo.sos_case_read(%s)',(case,))
    assert offered['assignment_offer'] is True and offered['can_track'] is False
    assert offered['incident_id']==original['incident_id'] and offered['internal_note']=='Private note'
    own=query(database,citizen,'SELECT trujillo.citizen_sos_cases(%s)',(case,))
    assert own['assignment_state']=='offered' and own['attention']=='none'
    with pytest.raises(psycopg.errors.InsufficientPrivilege):query(database,old,"SELECT trujillo.call_action(%s,'token')",(case,))
    with pytest.raises(psycopg.errors.InsufficientPrivilege):query(database,near,'SELECT trujillo.sos_navigation_target(%s)',(case,))
    assert query(database,citizen,'SELECT trujillo.citizen_call_operator(%s)',(case,))['state']=='waiting_assignment'
    accepted=query(database,near,'SELECT trujillo.claim_sos(%s)',(case,))
    assert accepted['can_track'] and accepted['assignment_state']=='assigned'
    query(database,near,"SELECT trujillo.call_action(%s,'accept')",(case,))
    assert query(database,citizen,"SELECT trujillo.call_action(%s,'status')",(case,))['can_join']
    with psycopg.connect(database) as c:
        assert c.execute('SELECT 1 FROM trujillo.sos_room_cleanup WHERE room=%s',(audio['room'],)).fetchone()
        assert c.execute('SELECT count(*) FROM trujillo.incidents WHERE id=%s',(original['incident_id'],)).fetchone()[0]==1
    query(database,near,'SELECT trujillo.operator_handoff(%s)',(case,))
    assert query(database,far,'SELECT trujillo.sos_case_read(%s)',(case,))['assignment_offer'] is True
    with psycopg.connect(database) as c:c.execute("UPDATE trujillo.sos_dispatch SET offer_expires_at=now()-interval '1 second' WHERE case_id=%s",(case,))
    query(database,None,'SELECT trujillo.sos_dispatch_tick()')
    own=query(database,citizen,'SELECT trujillo.citizen_sos_cases(%s)',(case,))
    assert own['assignment_state']=='searching' and own['attention']=='none'
    query(database,citizen,"SELECT trujillo.call_action(%s,'end')",(case,))
    query(database,old,'SELECT trujillo.operator_heartbeat(false)')
    query(database,old,'SELECT trujillo.operator_position(-8.11,-79.03,10,clock_timestamp())')
    with psycopg.connect(database) as c:
        assert c.execute('SELECT online FROM trujillo.operator_availability WHERE user_id=%s',(old,)).fetchone()[0] is False
    query(database,old,'SELECT trujillo.operator_begin_duty()')
    query(database,None,'SELECT trujillo.sos_dispatch_tick()')
    assert query(database,citizen,'SELECT trujillo.citizen_sos_cases(%s)',(case,))['assignment_state']=='searching'
