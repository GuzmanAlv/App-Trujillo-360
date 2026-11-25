from uuid import uuid4
import psycopg
import pytest
from test_sos_cases_database import database


def test_zone_filters_notifications_but_keeps_global_map_and_total(database):
    citizen,near,far,unknown=[uuid4() for _ in range(4)]
    with psycopg.connect(database) as c:
        for uid,role in [(citizen,'citizen'),(near,'operator'),(far,'operator'),(unknown,'operator')]:
            c.execute("INSERT INTO trujillo.users(id,auth_provider,auth_subject,display_name,role) VALUES(%s,'firebase',%s,'Test',%s)",(uid,str(uid),role))
    def query(uid,sql,args=(),many=False):
        with psycopg.connect(database) as c:
            c.execute("SELECT set_config('app.firebase_uid',%s,true)",(str(uid),))
            c.execute('SET LOCAL ROLE trujillo_api')
            cur=c.execute(sql,args)
            return [r[0] for r in cur] if many else cur.fetchone()[0]
    for uid in (near,far,unknown):
        query(uid,'SELECT trujillo.push_register(%s,%s,false,true,NULL,NULL,500,false)',(uuid4(),'zone-token-'+str(uuid4())))
    query(near,'SELECT trujillo.operator_position(-8.1,-79,10,clock_timestamp())')
    query(far,'SELECT trujillo.operator_position(-8.4,-79,10,clock_timestamp())')
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        query(citizen,'SELECT trujillo.operator_position(-8.1,-79,10,clock_timestamp())')
    with pytest.raises(psycopg.errors.InvalidParameterValue):
        query(near,'SELECT trujillo.operator_position(-8.1,-79,500,clock_timestamp())')
    with pytest.raises(psycopg.errors.InvalidParameterValue):
        query(near,"SELECT trujillo.operator_position(-8.1,-79,10,clock_timestamp()-interval '2 minutes')")
    case=query(citizen,'SELECT trujillo.submit_sos(%s,-8.11,-79)',(uuid4(),))['id']
    for uid,in_range in [(near,True),(far,False),(unknown,False)]:
        rows=query(uid,'SELECT trujillo.operator_sos_map_data()',many=True)
        row=next(r for r in rows if r['id']==case)
        assert row['alert_in_range'] is in_range and row['available'] is True
        assert query(uid,'SELECT trujillo.sos_case_read(%s)',(case,))['alert_in_range'] is in_range
    with psycopg.connect(database) as c:
        assert c.execute('SELECT count(*) FROM trujillo.push_outbox WHERE target_id=%s',(case,)).fetchone()[0]==1
        c.execute('SET LOCAL ROLE trujillo_api')
        job=c.execute('SELECT trujillo.push_claim()').fetchone()[0]
        assert job['account_uid']==str(near) and job['target_id']==case
        c.execute("SELECT trujillo.push_finish(%s,%s,'sent')",(job['job_id'],job['lease']))
        assert c.execute('SELECT trujillo.push_claim()').fetchone()[0] is None
    # Re-check distance when delivering a queued job: moving away silences it.
    query(near,'SELECT trujillo.operator_position(-7.976,-79,10,clock_timestamp())')
    query(far,'SELECT trujillo.operator_position(-7.973,-79,10,clock_timestamp())')
    for uid,in_range in [(near,True),(far,False)]:
        row=next(r for r in query(uid,'SELECT trujillo.operator_sos_map_data()',many=True) if r['id']==case)
        assert row['alert_in_range'] is in_range
    second_citizen=uuid4()
    with psycopg.connect(database) as c:
        c.execute("INSERT INTO trujillo.users(id,auth_provider,auth_subject,display_name,role) VALUES(%s,'firebase',%s,'Second citizen','citizen')",(second_citizen,str(second_citizen)))
    query(second_citizen,'SELECT trujillo.submit_sos(%s,-8.11,-79)',(uuid4(),))
    query(near,'SELECT trujillo.operator_position(-8.4,-79,10,clock_timestamp())')
    with psycopg.connect(database) as c:
        c.execute('SET LOCAL ROLE trujillo_api')
        assert c.execute('SELECT trujillo.push_claim()').fetchone()[0]['skipped'] is True
    # Missing/stale GPS never causes a city-wide alert.
    with psycopg.connect(database) as c:
        c.execute("UPDATE trujillo.operator_presence SET latitude=-8.1,observed_at=now()-interval '11 minutes' WHERE user_id=%s",(near,))
        c.execute("INSERT INTO trujillo.help_requests(user_id,request_id,category,place,description,latitude,longitude,submitted_priority,priority,source) SELECT %s,gen_random_uuid(),'Auxilio','SOS','',-8.12,-79,'Alta','Alta','sos' FROM generate_series(1,201)",(citizen,))
    rows=query(near,'SELECT trujillo.operator_sos_map_data()',many=True)
    assert len(rows)==203 and all(r['alert_in_range'] is False for r in rows)
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        query(citizen,'SELECT trujillo.operator_sos_map_data()',many=True)
    with psycopg.connect(database) as c:
        c.execute('SET LOCAL ROLE trujillo_api')
        with pytest.raises(psycopg.errors.InsufficientPrivilege):c.execute('SELECT * FROM trujillo.operator_presence')
