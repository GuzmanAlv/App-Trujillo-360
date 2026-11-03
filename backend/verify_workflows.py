"""Exercise real grants, RLS boundaries and workflow transitions; always rollback."""
from datetime import datetime,timezone,timedelta
from uuid import uuid4
import psycopg
from psycopg import sql
from app.db import connect
from contextlib import contextmanager
from unittest.mock import patch
from app.reports import ReportInput, submit_report
from fastapi import HTTPException

def main():
    with connect(admin=True) as conn:
        try:
            # Membership is granted only in this transaction and rolled back.
            admin=conn.execute('SELECT current_user').fetchone()[0]
            conn.execute(sql.SQL('GRANT trujillo_api TO {}').format(sql.Identifier(admin)))
            prefix='workflow-check-'+str(uuid4())
            ids=[]
            for i,role in enumerate(('citizen','citizen','operator')):
                ids.append(conn.execute("INSERT INTO trujillo.users(auth_provider,auth_subject,display_name,role) VALUES('firebase',%s,'Prueba',%s) RETURNING id",(prefix+str(i),role)).fetchone()[0])
            def as_user(i):
                conn.execute('RESET ROLE')
                conn.execute("SELECT set_config('app.firebase_uid',%s,true)",(prefix+str(i),))
                conn.execute('SET LOCAL ROLE trujillo_api')
            def denied(query,args=(),error=psycopg.errors.InsufficientPrivilege):
                try:
                    with conn.transaction():conn.execute(query,args).fetchall()
                except error:pass
                else:raise AssertionError('Unauthorized or invalid operation accepted')
            as_user(0)
            request=uuid4()
            args=(request,'Auxilio','Referencia','Caso ficticio',-30.123,-60.123,'Alta')
            h=conn.execute('SELECT trujillo.submit_help(%s,%s,%s,%s,%s,%s,%s)',args).fetchone()[0]
            assert conn.execute('SELECT trujillo.submit_help(%s,%s,%s,%s,%s,%s,%s)',args).fetchone()[0]['id']==h['id']
            denied('SELECT * FROM trujillo.list_help(true)')
            denied("UPDATE trujillo.users SET role='operator' WHERE id=%s",(ids[0],))
            denied('SELECT * FROM trujillo.operator_incidents()')
            denied('SELECT * FROM trujillo.operator_incident_reports(%s)',(uuid4(),))
            as_user(1)
            assert conn.execute('SELECT * FROM trujillo.list_help(false)').fetchall()==[]
            denied("SELECT trujillo.update_help(%s,'En revisión','Alta','Prueba inválida')",(h['id'],))
            as_user(2)
            assert any(row[0]['id']==h['id'] for row in conn.execute('SELECT * FROM trujillo.list_help(true)'))
            denied("SELECT trujillo.update_help(%s,'Cerrada','Alta','No puede saltar revisión')",(h['id'],),psycopg.errors.InvalidParameterValue)
            conn.execute("SELECT trujillo.update_help(%s,'En revisión','Media','Revisado en prueba')",(h['id'],))
            conn.execute("SELECT trujillo.update_help(%s,'Cerrada','Media','Fin de prueba')",(h['id'],))
            as_user(0)
            own=conn.execute('SELECT * FROM trujillo.list_help(false)').fetchone()[0]
            assert own['stage']=='Cerrada' and len(own['events'])==3
            # Retry retains the initial priority after the operator changes it.
            assert conn.execute('SELECT trujillo.submit_help(%s,%s,%s,%s,%s,%s,%s)',args).fetchone()[0]['priority']=='Media'
            # Exercise the HTTP handler against real grants in this rolled-back transaction.
            @contextmanager
            def borrowed_connection():
                with conn.transaction():
                    yield conn
            combined = ReportInput(request_id=uuid4(), category='Riesgo', place='Prueba unificada',
                description='Caso ficticio', latitude=-31.123, longitude=-61.123,
                occurred_at=datetime.now(timezone.utc)-timedelta(minutes=1), priority='Alta')
            with patch('app.reports.connect', borrowed_connection):
                saved = submit_report(combined, {'sub':prefix+'0'})
                again = submit_report(combined, {'sub':prefix+'0'})
                assert saved['id']==again['id'] and saved['help_request_id']==again['help_request_id']
                conflict = combined.model_copy(update={'request_id':uuid4()})
                conn.execute('SELECT trujillo.submit_help(%s,%s,%s,%s,%s,%s,%s)',
                    (conflict.request_id,conflict.category,conflict.place,conflict.description,
                     conflict.latitude,conflict.longitude,'Baja'))
                try:
                    submit_report(conflict, {'sub':prefix+'0'})
                except HTTPException as error:
                    assert error.status_code==409
                else:
                    raise AssertionError('Mismatched help request accepted')
                assert conn.execute('SELECT count(*) FROM trujillo.reports WHERE request_id=%s',
                    (conflict.request_id,)).fetchone()[0]==0, 'Partial report must roll back'
            as_user(2)
            inbox=[row[0] for row in conn.execute('SELECT * FROM trujillo.list_help(true)')]
            assert sum(row['id']==saved['help_request_id'] for row in inbox)==1
            assert next(row for row in inbox if row['id']==saved['help_request_id'])['priority']=='Alta'
            as_user(0)
            timestamp=datetime.now(timezone.utc)-timedelta(hours=1)
            report=conn.execute('SELECT trujillo.submit_report(%s,%s,%s,%s,%s,%s,%s)',(uuid4(),'Robo','Referencia','Privado',-30.123,-60.123,timestamp)).fetchone()[0]
            incident=report['incident_id']
            assert not any(str(row[0])==incident for row in conn.execute('SELECT * FROM trujillo.nearby_incidents(-30.123,-60.123,1000)'))
            as_user(2)
            conn.execute("SELECT trujillo.review_incident(%s,'verified','Validado en prueba')",(incident,))
            as_user(0)
            assert any(str(row[0])==incident for row in conn.execute('SELECT * FROM trujillo.nearby_incidents(-30.123,-60.123,1000)'))
            assert conn.execute('SELECT * FROM trujillo.incident_density(-30.124,-30.122,-60.124,-60.122,-1)').fetchall()
            conn.execute('RESET ROLE')
            conn.execute("UPDATE trujillo.incidents SET occurred_at=now()-interval '8 days' WHERE id=%s",(incident,))
            as_user(0)
            assert not any(str(row[0])==incident for row in conn.execute('SELECT * FROM trujillo.nearby_incidents(-30.123,-60.123,1000)'))
            assert conn.execute('SELECT * FROM trujillo.incident_density(-30.124,-30.122,-60.124,-60.122,-1)').fetchall()
            print('Permisos, aislamiento, reintentos, seguimiento y ventanas verificados. Fixtures revertidos.')
        finally:conn.rollback()

if __name__=='__main__':main()
