"""Real permissions, geographic targeting and durable queue checks. Always rollback."""
from uuid import uuid4
from datetime import datetime, timezone, timedelta
from psycopg import sql, errors
from app.db import ROOT, connect

def main():
    with connect(admin=True) as conn:
        try:
            if not conn.execute("SELECT to_regclass('trujillo.push_migrations')").fetchone()[0]:
                conn.execute((ROOT/'migrations/013_push.sql').read_text(encoding='utf-8'))
            admin=conn.execute('SELECT current_user').fetchone()[0]
            conn.execute(sql.SQL('GRANT trujillo_api TO {}').format(sql.Identifier(admin)))
            prefix='push-check-'+str(uuid4())
            users=[]
            for i,role in enumerate(('citizen','citizen','operator','citizen')):
                users.append(conn.execute("INSERT INTO trujillo.users(auth_provider,auth_subject,display_name,role) VALUES('firebase',%s,'Prueba',%s) RETURNING id",(prefix+str(i),role)).fetchone()[0])
            def as_user(i):
                conn.execute('RESET ROLE')
                conn.execute("SELECT set_config('app.firebase_uid',%s,true)",(prefix+str(i),))
                conn.execute('SET LOCAL ROLE trujillo_api')
            def denied(query,args=()):
                try:
                    with conn.transaction(): conn.execute(query,args).fetchall()
                except errors.InsufficientPrivilege: pass
                else: raise AssertionError('Unauthorized access accepted')
            devices=[uuid4() for _ in users]
            register='SELECT trujillo.push_register(%s,%s,%s,%s,%s,%s,%s)'
            for i in range(4):
                as_user(i)
                data=conn.execute(register,(devices[i],prefix+'-token-'+str(i),i!=2,i==2,-30.1 if i!=3 else -32.1,-60.1,500)).fetchone()[0]
                assert 'token' not in data
            as_user(0)
            denied(register,(devices[0],prefix+'-token-0',True,True,-30.1,-60.1,500))
            denied('SELECT * FROM trujillo.push_devices')
            as_user(1)
            assert conn.execute('SELECT trujillo.push_preferences(%s)',(devices[0],)).fetchone()[0] is None
            denied(register,(devices[0],prefix+'-token-1',True,False,-30.1,-60.1,500))
            # Report is pending: no citizen notifications. Deferred operator trigger sees final priority.
            as_user(0)
            request=uuid4()
            report=conn.execute('SELECT trujillo.submit_report(%s,%s,%s,%s,%s,%s,%s)',
                (request,'Robo','Prueba','Ficticio',-30.1,-60.1,datetime.now(timezone.utc)-timedelta(minutes=1))).fetchone()[0]
            help=conn.execute('SELECT trujillo.submit_help(%s,%s,%s,%s,%s,%s,%s)',(request,'Robo','Prueba','Ficticio',-30.1,-60.1,'Alta')).fetchone()[0]
            conn.execute('SET CONSTRAINTS ALL IMMEDIATE')
            conn.execute('RESET ROLE')
            jobs=conn.execute('SELECT kind,device_id FROM trujillo.push_outbox WHERE user_id=ANY(%s)',(users,)).fetchall()
            assert jobs==[('operator',devices[2])]
            as_user(2)
            denied('SELECT trujillo.push_operator_event(%s)',(uuid4(),))
            item=conn.execute('SELECT trujillo.push_claim()').fetchone()[0]
            assert item['kind']=='operator' and item['target_id']==help['id'] and 'Alta' in item['title']
            assert conn.execute('SELECT trujillo.push_claim()').fetchone()[0] is None, 'Lease must prevent double claiming'
            conn.execute('SELECT trujillo.push_finish(%s,%s,%s)',(item['job_id'],item['lease'],'sent'))
            # Citizen never receives the private help detail, even knowing its UUID.
            as_user(0)
            denied("SELECT trujillo.push_target('operator_help',%s)",(help['id'],))
            as_user(2)
            conn.execute("SELECT trujillo.review_incident(%s,'verified','Prueba validada')",(report['incident_id'],))
            conn.execute('RESET ROLE')
            targets=conn.execute("SELECT device_id FROM trujillo.push_outbox WHERE kind='citizen' AND user_id=ANY(%s)",(users,)).fetchall()
            assert set(x[0] for x in targets)==set(devices[:2]), 'Only opted-in nearby zones'
            as_user(2)
            conn.execute("SELECT trujillo.review_incident(%s,'verified','Otra revisión')",(report['incident_id'],))
            conn.execute('RESET ROLE')
            assert conn.execute("SELECT count(*) FROM trujillo.push_outbox WHERE kind='citizen' AND user_id=ANY(%s)",(users,)).fetchone()[0]==2
            # Opt-out before delivery cancels the queued notification.
            as_user(0)
            conn.execute(register,(devices[0],prefix+'-token-0',False,False,None,None,500))
            # Closed/discarded public events are rechecked, never sent stale.
            as_user(2)
            conn.execute("SELECT trujillo.review_incident(%s,'discarded','Caso descartado')",(report['incident_id'],))
            for _ in range(2):
                skipped=conn.execute('SELECT trujillo.push_claim()').fetchone()[0]
                assert skipped['skipped']
            as_user(0)
            try:
                with conn.transaction(): conn.execute("SELECT trujillo.push_target('citizen',%s)",(report['incident_id'],))
            except errors.NoDataFound: pass
            else: raise AssertionError('Discarded incident remained public')
            print('Push: permisos, zonas, urgencia, cola, deduplicación, leases y revocación verificados. Datos revertidos.')
        finally:
            conn.rollback()

if __name__=='__main__': main()
