"""Isolated PostgreSQL tests. Set PG_TEST_BIN to a directory containing initdb/pg_ctl.

Never uses app.db, .env, Supabase or the running local database.
"""
import os
import socket
import subprocess
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
from uuid import uuid4
import psycopg
import pytest

@pytest.fixture(scope='module')
def database(tmp_path_factory):
    binaries = os.getenv('PG_TEST_BIN')
    if not binaries:
        pytest.skip('Set PG_TEST_BIN for isolated PostgreSQL integration tests')
    root = tmp_path_factory.mktemp('call-postgres')
    data = root / 'data'
    def run(name, *args):
        with (root/'commands.log').open('ab') as log:
            subprocess.run([str(Path(binaries) / name), *map(str, args)], check=True, stdout=log, stderr=log, timeout=30)
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    run('initdb', '-D', data, '-U', 'postgres', '-A', 'trust', '--no-locale', '-E', 'UTF8')
    run('pg_ctl', '-D', data, '-l', root/'postgres.log', '-o', f'-h 127.0.0.1 -p {port}', '-w', 'start')
    dsn = f'host=127.0.0.1 port={port} user=postgres dbname=postgres'
    try:
        with psycopg.connect(dsn) as conn:
            conn.execute("CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE trujillo_api; CREATE SCHEMA extensions; CREATE EXTENSION postgis SCHEMA extensions;")
            for migration in sorted((Path(__file__).parents[1]/'migrations').glob('*.sql')):
                conn.execute(migration.read_text(encoding='utf-8'))
                if migration.name.startswith('001_'):
                    conn.execute('GRANT USAGE ON SCHEMA trujillo TO trujillo_api')
        yield dsn
    finally:
        run('pg_ctl', '-D', data, '-m', 'immediate', '-w', 'stop')


from psycopg.types.json import Jsonb

def arrive(database, query, operator, case, latitude, longitude):
    sql='SELECT trujillo.sos_arrival_check(%s,%s,%s,10,clock_timestamp())'
    assert query(operator,sql,(case,latitude,longitude))['attention']=='en_route'
    with psycopg.connect(database) as c:
        c.execute("UPDATE trujillo.sos_arrival_samples SET first_at=clock_timestamp()-interval '12 seconds', observed_at=clock_timestamp()-interval '12 seconds' WHERE case_id=%s",(case,))
    assert query(operator,sql,(case,latitude,longitude))['attention']=='on_scene'

def test_case_lifecycle_and_privacy(database):
    citizen, op, other = [uuid4() for _ in range(3)]
    with psycopg.connect(database) as c:
        for uid, role in [(citizen,'citizen'),(op,'operator'),(other,'operator')]:
            c.execute("INSERT INTO trujillo.users(id,auth_provider,auth_subject,display_name,role) VALUES(%s,'firebase',%s,'Test',%s)",(uid,str(uid),role))
    def query(user, sql, args=(), many=False):
        with psycopg.connect(database) as c:
            c.execute("SELECT set_config('app.firebase_uid',%s,true)",(str(user),))
            c.execute('SET LOCAL ROLE trujillo_api')
            cur=c.execute(sql,args)
            return cur.fetchall() if many else cur.fetchone()[0]
    case=query(citizen,'SELECT trujillo.submit_sos(%s,%s,%s)',(uuid4(),-8.11,-79.03))['id']
    query(citizen,"SELECT trujillo.call_action(%s,'start')",(case,))
    assert query(op,'SELECT trujillo.incoming_calls()')['id']==case
    query(op,"SELECT trujillo.call_action(%s,'accept')",(case,))
    query(citizen,"SELECT trujillo.call_action(%s,'end')",(case,))
    assert query(op,'SELECT trujillo.sos_case_read(%s)',(case,))['decision']=='pending'
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        query(citizen,'SELECT trujillo.sos_case_read(%s)',(case,))
    data=dict(action='confirm',category='Robo',latitude=-8.12,longitude=-79.04,
              place='Lugar confirmado',public_description='Descripción pública',internal_note='NO PUBLICAR',outcome='')
    def update(user, version, payload=data, request=None):
        return query(user,'SELECT trujillo.sos_case_update(%s,%s,%s,%s)',(case,request or uuid4(),version,Jsonb(payload)))
    with pytest.raises(psycopg.errors.InsufficientPrivilege): update(other,0)
    request=uuid4()
    result=update(op,0,request=request)
    incident=result['incident_id']
    assert result['attention']=='en_route'
    assert result['caller_latitude']==-8.11 and result['latitude']==-8.12
    assert update(op,0,request=request)['incident_id']==incident
    with pytest.raises(psycopg.errors.RaiseException): update(op,0)
    rows=query(citizen,'SELECT * FROM trujillo.map_incidents(-9,-7,-80,-78)',many=True)
    assert any(str(row[0])==incident and row[6]==0 for row in rows)
    public=query(citizen,'SELECT trujillo.public_case_fields(%s::uuid[])',([incident],))
    assert public['description']=='Descripción pública' and 'NO PUBLICAR' not in str(public)
    assert 'caller_latitude' not in public and 'internal_note' not in public
    push=query(citizen,"SELECT trujillo.push_target('citizen',%s)",(incident,))
    assert push['description']=='Descripción pública' and 'NO PUBLICAR' not in str(push)
    operator_rows=query(op,'SELECT trujillo.operator_incidents()',many=True)
    assert any(row[0].get('sos_case_id')==case for row in operator_rows)
    with pytest.raises(psycopg.errors.RaiseException):
        query(op,"SELECT trujillo.update_help(%s,'Descartada','Alta','No autorizado por este flujo')",(case,))
    with pytest.raises(psycopg.errors.RaiseException):
        query(op,"SELECT trujillo.review_incident(%s,'discarded','No autorizado por este flujo')",(incident,))
    assert query(citizen,'SELECT * FROM trujillo.incident_reports(%s)',(incident,),many=True)==[]
    assert query(citizen,'SELECT * FROM trujillo.community_photos(%s)',(incident,),many=True)==[]
    arrive(database,query,op,case,-8.12,-79.04)
    assert query(citizen,'SELECT trujillo.public_case_fields(%s::uuid[])',([incident],))['attention']=='on_scene'
    for action, version in [('resolve',2)]:
        result=update(op,version,{**data,'action':action,'outcome':'Atención concluida'})
        assert result['attention']==('resolved' if action=='resolve' else action)
        if action!='resolve':
            assert query(citizen,'SELECT trujillo.public_case_fields(%s::uuid[])',([incident],))['attention']==action
    assert len(result['events'])==3
    assert query(citizen,'SELECT * FROM trujillo.map_incidents(-9,-7,-80,-78)',many=True)==[]
    assert query(op,"SELECT * FROM trujillo.incident_density(-9,-7,-80,-78,-1)",many=True)
    with pytest.raises(psycopg.errors.RaiseException): update(op,4)
    with psycopg.connect(database) as c:
        assert c.execute('SELECT count(*) FROM trujillo.incidents').fetchone()[0]==1
        c.execute('SET LOCAL ROLE trujillo_api')
        with pytest.raises(psycopg.errors.InsufficientPrivilege): c.execute('SELECT * FROM trujillo.sos_case_events')


def test_concurrent_confirmations_pending_discard_and_suspension(database):
    citizen, op1, op2 = [uuid4() for _ in range(3)]
    with psycopg.connect(database) as c:
        for uid,role in [(citizen,'citizen'),(op1,'operator'),(op2,'operator')]:
            c.execute("INSERT INTO trujillo.users(id,auth_provider,auth_subject,display_name,role) VALUES(%s,'firebase',%s,'Test',%s)",(uid,str(uid),role))
    def query(user,sql,args=(),many=False):
        with psycopg.connect(database) as c:
            c.execute("SELECT set_config('app.firebase_uid',%s,true)",(str(user),))
            c.execute('SET LOCAL ROLE trujillo_api')
            cur=c.execute(sql,args)
            return cur.fetchall() if many else cur.fetchone()[0]
    def new_case():
        return query(citizen,'SELECT trujillo.submit_sos(%s,-8.11,-79.03)',(uuid4(),))['id']
    data=dict(action='confirm',category='Auxilio',latitude=-8.10,longitude=-79.02,
              place='Lugar exacto',public_description='Ayuda confirmada',internal_note='Solo uso interno',outcome='')
    case=new_case()
    def update(op,version,payload=data,case_id=case):
        return query(op,'SELECT trujillo.sos_case_update(%s,%s,%s,%s)',(case_id,uuid4(),version,Jsonb(payload)))
    with pytest.raises(psycopg.errors.RaiseException): update(op1,0,{**data,'action':'on_scene'})
    with pytest.raises(psycopg.errors.InsufficientPrivilege): update(citizen,0)
    def race(op):
        try: return update(op,0)
        except (psycopg.errors.RaiseException,psycopg.errors.InsufficientPrivilege): return None
    with ThreadPoolExecutor(max_workers=2) as pool: results=list(pool.map(race,[op1,op2]))
    assert results.count(None)==1
    winner=op1 if results[0] else op2
    incident=next(r for r in results if r)['incident_id']
    with psycopg.connect(database) as c:
        assert c.execute('SELECT count(*) FROM trujillo.sos_cases WHERE id=%s AND incident_id=%s',(case,incident)).fetchone()[0]==1
    with pytest.raises(psycopg.errors.RaiseException): update(winner,1,{**data,'action':'pending'})
    other_case=new_case()
    query(citizen,"SELECT trujillo.call_action(%s,'start')",(other_case,))
    with psycopg.connect(database) as c:
        c.execute("UPDATE trujillo.call_sessions SET expires_at=now()-interval '1 second' WHERE id=%s",(other_case,))
    assert query(op1,"SELECT trujillo.call_action(%s,'status')",(other_case,))['state']=='unanswered'
    assert query(op1,'SELECT trujillo.sos_case_read(%s)',(other_case,))['decision']=='pending'
    pending=update(op1,0,{**data,'action':'pending'},other_case)
    assert pending['incident_id'] is None
    discarded=update(op1,1,{**data,'action':'discard'},other_case)
    assert discarded['decision']=='discarded' and discarded['incident_id'] is None
    with pytest.raises(psycopg.errors.RaiseException): update(op1,2,data,other_case)
    own_case=query(op1,'SELECT trujillo.submit_sos(%s,-8.11,-79.03)',(uuid4(),))['id']
    with pytest.raises(psycopg.errors.InsufficientPrivilege): update(op1,0,data,own_case)
    with psycopg.connect(database) as c:
        c.execute("UPDATE trujillo.users SET status='suspended',suspension_reason='Test' WHERE id=%s",(winner,))
    with pytest.raises(psycopg.errors.InsufficientPrivilege): query(winner,'SELECT trujillo.sos_case_read(%s)',(case,))
