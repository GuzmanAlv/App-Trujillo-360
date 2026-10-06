"""Concurrent pilot test. Temporary committed fixtures are deleted in finally."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone, timedelta
from threading import Barrier
from uuid import uuid4
import random
import psycopg
from psycopg.types.json import Jsonb
from app.db import connect

uids=['concurrent-test-'+str(uuid4()) for _ in range(4)]
when=datetime.now(timezone.utc)-timedelta(days=1)
lng=random.uniform(-140,-110)
query='SELECT trujillo.submit_report_with_photos(%s,%s,%s,%s,%s,%s,%s,%s)'
barrier=Barrier(3)

def send(index):
    with connect() as conn:
        conn.execute("SELECT set_config('app.firebase_uid',%s,true)",(uids[index],))
        if index<3: barrier.wait(timeout=15)
        return conn.execute(query,(uuid4(),'Riesgo','Prueba simultánea','',-70,lng,when,Jsonb([]))).fetchone()[0]

try:
    with connect(admin=True) as conn:
        assert conn.execute('''SELECT count(*) FROM trujillo.incidents WHERE
            extensions.ST_DWithin(location,extensions.ST_SetSRID(extensions.ST_MakePoint(%s,-70),4326)::extensions.geography,1000)''',(lng,)).fetchone()[0]==0
        for uid in uids:
            conn.execute("INSERT INTO trujillo.users(auth_provider,auth_subject,display_name) VALUES('firebase',%s,'Prueba temporal')",(uid,))
        conn.execute("UPDATE trujillo.users SET status='suspended', suspension_reason='Prueba temporal' WHERE auth_subject=%s",(uids[3],))
    with ThreadPoolExecutor(max_workers=3) as pool:
        results=list(pool.map(send,range(3)))
    assert len({result['incident_id'] for result in results})==1
    assert sorted(result['corroboration_count'] for result in results)==[1,2,3]
    assert any(result['status']=='corroborated' for result in results)
    try:
        send(3)
        raise AssertionError('Suspended user accepted')
    except psycopg.errors.InsufficientPrivilege:
        pass
    print('OK: tres envíos simultáneos crean un solo incidente corroborado; cuenta suspendida rechazada.')
finally:
    with connect(admin=True) as conn:
        user_ids=[row[0] for row in conn.execute("SELECT id FROM trujillo.users WHERE auth_provider='firebase' AND auth_subject=ANY(%s)",(uids,))]
        if user_ids:
            conn.execute('DELETE FROM trujillo.report_photos WHERE report_id IN (SELECT id FROM trujillo.reports WHERE user_id=ANY(%s))',(user_ids,))
            incident_ids=[row[0] for row in conn.execute('DELETE FROM trujillo.reports WHERE user_id=ANY(%s) RETURNING incident_id',(user_ids,))]
            if incident_ids:
                conn.execute('DELETE FROM trujillo.incidents i WHERE id=ANY(%s) AND NOT EXISTS(SELECT 1 FROM trujillo.reports r WHERE r.incident_id=i.id)',(incident_ids,))
            conn.execute('DELETE FROM trujillo.users WHERE id=ANY(%s)',(user_ids,))
    print('Fixtures temporales eliminados.')
