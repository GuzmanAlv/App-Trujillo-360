"""Real transaction test; all fixtures and reports are rolled back."""
from uuid import uuid4
from datetime import datetime, timezone
import psycopg
from app.db import connect

with connect() as conn:
    try:
        uid='test-'+str(uuid4())
        conn.execute("SELECT set_config('app.firebase_uid',%s,true)",(uid,))
        conn.execute("INSERT INTO trujillo.users(auth_provider,auth_subject,display_name) VALUES('firebase',%s,'Prueba')",(uid,))
        args=(uuid4(),'Robo','Prueba transaccional','',-8.11,-79.02,datetime.now(timezone.utc))
        query='SELECT trujillo.submit_report(%s,%s,%s,%s,%s,%s,%s)'
        first=conn.execute(query,args).fetchone()[0]
        second=conn.execute(query,args).fetchone()[0]
        assert first==second and first['status']=='pending'
        try:
            with conn.transaction():
                conn.execute(query,(args[0],'Auxilio',*args[2:]))
            raise AssertionError('Changed payload accepted')
        except psycopg.errors.RaiseException:
            pass
        conn.execute("SELECT set_config('app.firebase_uid',%s,true)",(uid+'-other',))
        try:
            with conn.transaction():
                conn.execute(query,args)
            raise AssertionError('Unknown identity accepted')
        except psycopg.errors.InsufficientPrivilege:
            pass
        print('OK: reporte pendiente, reintento sin duplicado, conflicto y rechazo de identidad ajena.')
    finally:
        conn.rollback()
