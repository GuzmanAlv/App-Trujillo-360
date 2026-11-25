from concurrent.futures import ThreadPoolExecutor
from uuid import uuid4
import psycopg
import pytest
from test_sos_cases_database import database
from test_sos_dispatch_database import users, query, confirm


def make_call(database, user):
    case=query(database,user,'SELECT trujillo.submit_sos(%s,-8.11,-79.03)',(uuid4(),))['id']
    call=query(database,user,"SELECT trujillo.call_action(%s,'start')",(case,))
    return case,call['room'].removeprefix('sos-'+case+'-')


def test_simultaneous_selection_keeps_other_case_visible(database):
    first,second,op=users(database,'citizen','citizen','operator')
    cases=[make_call(database,u) for u in (first,second)]
    def take(item):return query(database,op,'SELECT trujillo.take_sos_call(%s,%s)',item)
    with ThreadPoolExecutor(max_workers=2) as pool:results=list(pool.map(take,cases))
    assert sum(r.get('call_accepted') is True for r in results)==1
    assert sum(r.get('error_code')=='SOS_BUSY' for r in results)==1
    index=next(i for i,r in enumerate(results) if r.get('call_accepted'))
    active=cases[index][0]; other=cases[1-index][0]
    assert results[index]['call']['id']==active
    rows=query(database,op,'SELECT trujillo.operator_sos_map_data()',many=True)
    assert next(r for r in rows if r['id']==active)['claimed_by_me'] is True
    assert next(r for r in rows if r['id']==other)['available'] is True
    portal=query(database,op,'SELECT trujillo.operator_help_cases()',many=True)
    assert {active,other}<={r['id'] for r in portal}
    assert query(database,(first,second)[1-index],'SELECT trujillo.citizen_sos_map_cases(NULL)',many=True)[0]['id']==other
    query(database,op,"SELECT trujillo.call_action(%s,'end')",(active,))
    assert take(cases[1-index])['call_accepted'] is True
    rows=query(database,op,'SELECT trujillo.operator_sos_map_data()',many=True)
    assert next(r for r in rows if r['id']==active)['available'] is True


def test_status_is_read_only_and_does_not_wait_for_assignment_lock(database):
    citizen,op=users(database,'citizen','operator');case,generation=make_call(database,citizen)
    query(database,op,'SELECT trujillo.take_sos_call(%s,%s)',(case,generation))
    with psycopg.connect(database) as lock:
        before=lock.execute('SELECT claim_expires_at FROM trujillo.sos_cases WHERE id=%s',(case,)).fetchone()[0]
        lock.execute('SELECT pg_advisory_xact_lock(360017)')
        with psycopg.connect(database) as c:
            c.execute("SELECT set_config('app.firebase_uid',%s,true)",(str(op),))
            c.execute("SET LOCAL ROLE trujillo_api; SET LOCAL statement_timeout='750ms'")
            assert c.execute("SELECT trujillo.call_action(%s,'status')",(case,)).fetchone()[0]['state']=='accepted'
        after=lock.execute('SELECT claim_expires_at FROM trujillo.sos_cases WHERE id=%s',(case,)).fetchone()[0]
        assert before==after
    assert query(database,op,'SELECT trujillo.call_heartbeat(%s)',(case,))['owned'] is True
    with pytest.raises(psycopg.errors.InsufficientPrivilege):query(database,citizen,'SELECT trujillo.call_heartbeat(%s)',(case,))


def test_old_end_does_not_close_new_generation_and_stale_take_preserves_reservation(database):
    citizen,second,op=users(database,'citizen','citizen','operator')
    case,generation=make_call(database,citizen)
    query(database,op,'SELECT trujillo.take_sos_call(%s,%s)',(case,generation))
    query(database,op,"SELECT trujillo.call_action(%s,'end')",(case,))
    other,new_generation=make_call(database,second)
    assert query(database,op,'SELECT trujillo.take_sos_call(%s,%s)',(other,uuid4()))['error_code']=='SOS_CALL_CHANGED'
    with psycopg.connect(database) as c:
        assert c.execute('SELECT operator_id FROM trujillo.sos_cases WHERE id=%s',(case,)).fetchone()[0]==op
    newer=query(database,op,"SELECT trujillo.call_action(%s,'callback')",(case,))
    assert newer['room']!='sos-'+case+'-'+generation
    assert query(database,citizen,'SELECT trujillo.end_call_generation(%s,%s)',(case,generation))['stale'] is True
    assert query(database,citizen,"SELECT trujillo.call_action(%s,'status')",(case,))['state']=='waiting'


def test_confirmed_case_is_never_silently_released(database):
    citizen,second,op=users(database,'citizen','citizen','operator')
    case,generation=make_call(database,citizen)
    query(database,op,'SELECT trujillo.take_sos_call(%s,%s)',(case,generation))
    query(database,op,"SELECT trujillo.call_action(%s,'end')",(case,))
    confirm(database,op,case)
    other,generation=make_call(database,second)
    assert query(database,op,'SELECT trujillo.take_sos_call(%s,%s)',(other,generation))['error_code']=='SOS_BUSY'
    with psycopg.connect(database) as c:
        assert c.execute('SELECT operator_id FROM trujillo.sos_cases WHERE id=%s',(case,)).fetchone()[0]==op


def test_competing_operators_cannot_accept_same_audio(database):
    citizen,first,second=users(database,'citizen','operator','operator')
    case,generation=make_call(database,citizen)
    with ThreadPoolExecutor(max_workers=2) as pool:
        results=list(pool.map(lambda op:query(database,op,'SELECT trujillo.take_sos_call(%s,%s)',(case,generation)),(first,second)))
    assert sum(r.get('call_accepted') is True for r in results)==1
    assert sum(r.get('error_code')=='SOS_TAKEN' for r in results)==1
    loser=(first,second)[next(i for i,r in enumerate(results) if r.get('error_code'))]
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        query(database,loser,'SELECT trujillo.end_call_generation(%s,%s)',(case,uuid4()))


def test_unchanged_identity_can_sync_without_writing_locked_account(database):
    citizen,=users(database,'citizen')
    with psycopg.connect(database) as c:
        c.execute('UPDATE trujillo.users SET auth_email=%s WHERE id=%s',('test@example.com',citizen))
    with psycopg.connect(database) as lock:
        lock.execute('SELECT * FROM trujillo.users WHERE id=%s FOR SHARE',(citizen,))
        with psycopg.connect(database) as c:
            c.execute("SELECT set_config('app.firebase_uid',%s,true)",(str(citizen),))
            c.execute("SET LOCAL ROLE trujillo_api; SET LOCAL statement_timeout='750ms'")
            c.execute("SELECT trujillo.sync_identity_email('test@example.com')")
