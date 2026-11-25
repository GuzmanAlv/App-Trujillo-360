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
            conn.execute('''CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE trujillo_api;
            CREATE SCHEMA trujillo;
            GRANT USAGE ON SCHEMA trujillo TO trujillo_api;
            CREATE TABLE trujillo.users(id uuid PRIMARY KEY, role text, status text, auth_provider text, auth_subject text);
            CREATE TABLE trujillo.help_requests(id uuid PRIMARY KEY,user_id uuid,source text,stage text,priority text);
            CREATE TABLE trujillo.help_events(request_id uuid,actor_id uuid,stage text,priority text,reason text);''')
            workflows = (Path(__file__).parents[1]/'migrations/012_workflows.sql').read_text(encoding='utf-8')
            actor = workflows.split('CREATE FUNCTION trujillo.current_actor')[1].split('CREATE FUNCTION trujillo.submit_help')[0]
            conn.execute('CREATE FUNCTION trujillo.current_actor'+actor)
            conn.execute((Path(__file__).parents[1]/'migrations/017_calls.sql').read_text(encoding='utf-8'))
        yield dsn
    finally:
        run('pg_ctl', '-D', data, '-m', 'immediate', '-w', 'stop')

def test_exclusive_assignment_permissions_and_lifecycle(database):
    citizen, outsider, op1, op2 = [uuid4() for _ in range(4)]
    call, second = uuid4(), uuid4()
    with psycopg.connect(database) as conn:
        for user, role in [(citizen,'citizen'), (outsider,'citizen'),(op1,'operator'),(op2,'operator')]:
            conn.execute("INSERT INTO trujillo.users VALUES(%s,%s,'active','firebase',%s)", (user,role,str(user)))
        for request in (call,second):
            conn.execute("INSERT INTO trujillo.help_requests VALUES(%s,%s,'sos','Recibida','Alta')", (request,citizen))
    def action(user, operation, request=call):
        with psycopg.connect(database) as conn:
            conn.execute("SELECT set_config('app.firebase_uid',%s,true)", (str(user),))
            conn.execute('SET LOCAL ROLE trujillo_api')
            return conn.execute('SELECT trujillo.call_action(%s,%s)', (request, operation)).fetchone()[0]
    assert action(citizen,'start')['state'] == 'waiting'
    assert action(citizen,'start')['id'] == str(call)
    with pytest.raises(psycopg.errors.RaiseException):
        action(citizen,'start',second)
    for user, operation in [(outsider,'status'),(citizen,'accept'),(citizen,'token')]:
        with pytest.raises(psycopg.errors.InsufficientPrivilege):
            action(user,operation)
    def accept(user):
        try:
            action(user,'accept')
            return user
        except psycopg.errors.RaiseException:
            return None
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(accept,[op1,op2]))
    assert results.count(None) == 1
    assigned = next(user for user in results if user)
    other = op2 if assigned == op1 else op1
    assert action(assigned,'accept')['state'] == 'accepted'
    assert action(citizen,'token')['can_join'] is True
    assert action(assigned,'token')['can_join'] is True
    for operation in ('token','end'):
        with pytest.raises(psycopg.errors.InsufficientPrivilege):
            action(other,operation)
    assert action(citizen,'end')['state'] == 'ended'
    assert action(assigned,'end')['state'] == 'ended'
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        action(citizen,'token')
    action(citizen,'start',second)
    with psycopg.connect(database) as conn:
        conn.execute("UPDATE trujillo.call_sessions SET expires_at=now()-interval '1 second' WHERE id=%s", (second,))
    assert action(citizen,'status',second)['state'] == 'unanswered'
    with pytest.raises(psycopg.errors.RaiseException):
        action(op1,'accept',second)
    with psycopg.connect(database) as conn:
        conn.execute('SET LOCAL ROLE trujillo_api')
        with pytest.raises(psycopg.errors.InsufficientPrivilege):
            conn.execute('SELECT * FROM trujillo.call_sessions')
