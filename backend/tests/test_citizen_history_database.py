from uuid import uuid4
import psycopg
import pytest
from test_sos_cases_database import database


def test_history_includes_old_closed_pending_and_discarded_without_other_owners(database):
    owner,other,operator=[uuid4() for _ in range(3)]
    with psycopg.connect(database) as c:
        for uid,role in [(owner,'citizen'),(other,'citizen'),(operator,'operator')]:
            c.execute("INSERT INTO trujillo.users(id,auth_provider,auth_subject,display_name,role) VALUES(%s,'firebase',%s,'History',%s)",(uid,str(uid),role))
        for uid,n in [(owner,55),(other,1)]:
            c.execute("""INSERT INTO trujillo.help_requests(user_id,request_id,category,place,description,latitude,longitude,submitted_priority,priority,source,received_at)
             SELECT %s,gen_random_uuid(),'Auxilio','Lugar propio','',-8.1,-79,'Alta','Alta','sos',now()-interval '60 days'-make_interval(secs=>s)
             FROM generate_series(1,%s) s""",(uid,n))
        ids=[r[0] for r in c.execute('SELECT id FROM trujillo.help_requests WHERE user_id=%s ORDER BY received_at DESC,id DESC',(owner,))]
        c.execute("UPDATE trujillo.help_requests SET stage='Cerrada' WHERE id=%s",(ids[0],))
        c.execute("INSERT INTO trujillo.sos_cases(id,operator_id,category,latitude,longitude,decision,attention,internal_note,public_description) VALUES(%s,%s,'Robo',-8.1,-79,'confirmed','resolved','NOT PUBLIC','Descripción del hecho')",(ids[0],operator))
        c.execute("UPDATE trujillo.help_requests SET stage='Descartada' WHERE id=%s",(ids[1],))
    def read(uid,limit=50,offset=0):
        with psycopg.connect(database) as c:
            c.execute("SELECT set_config('app.firebase_uid',%s,true)",(str(uid),))
            c.execute('SET LOCAL ROLE trujillo_api')
            return [r[0] for r in c.execute('SELECT trujillo.citizen_sos_history(%s,%s)',(limit,offset))]
    first,last=read(owner),read(owner,50,50)
    assert len(first)==50 and len(last)==5
    assert [r['id'] for r in first+last]==list(map(str,ids))
    assert first[0]['attention']=='resolved' and first[0]['category']=='Robo'
    assert first[1]['decision']=='discarded' and first[2]['decision']=='pending'
    assert 'NOT PUBLIC' not in str(first) and 'internal_note' not in first[0] and 'operator_id' not in first[0]
    assert len(read(other))==1 and read(other)[0]['id'] not in {r['id'] for r in first+last}
    assert read(operator)==[] and read(owner,50,100)==[]
    with pytest.raises(psycopg.errors.InvalidParameterValue):read(owner,101)
    with pytest.raises(psycopg.errors.InvalidParameterValue):read(owner,50,-1)
    with pytest.raises(psycopg.errors.InsufficientPrivilege):read(uuid4())
    with psycopg.connect(database) as c:c.execute("UPDATE trujillo.users SET status='suspended',suspension_reason='Test' WHERE id=%s",(owner,))
    with pytest.raises(psycopg.errors.InsufficientPrivilege):read(owner)
