"""Real Supabase checks; all fixtures rolled back."""
from datetime import datetime, timezone, timedelta
from uuid import uuid4
import psycopg
from psycopg.types.json import Jsonb
from app.db import connect

QUERY='SELECT trujillo.submit_report_with_photos(%s,%s,%s,%s,%s,%s,%s,%s)'
with connect() as conn:
    try:
        users=['corroboration-test-'+str(uuid4()) for _ in range(5)]
        when=datetime.now(timezone.utc)-timedelta(hours=2)
        def as_user(index):
            conn.execute("SELECT set_config('app.firebase_uid',%s,true)",(users[index],))
            conn.execute("INSERT INTO trujillo.users(auth_provider,auth_subject,display_name) VALUES('firebase',%s,'Prueba') ON CONFLICT DO NOTHING",(users[index],))
        def send(index,lat=-60,lng=-140,category='Robo',offset=0):
            as_user(index)
            args=(uuid4(),category,'Prueba corroboración','',lat,lng,when+timedelta(seconds=offset),Jsonb([]))
            return conn.execute(QUERY,args).fetchone()[0],args
        first,args=send(0)
        assert first['corroboration_count']==1 and first['status']=='pending'
        assert conn.execute(QUERY,args).fetchone()[0]==first
        try:
            with conn.transaction(): send(0)
            raise AssertionError('Duplicate account counted')
        except psycopg.errors.NoDataFound: pass
        second,_=send(1,lat=-59.9996,offset=30)
        assert second['incident_id']==first['incident_id'] and second['corroboration_count']==2
        third,_=send(2,lat=-60.0003,offset=60)
        assert third['incident_id']==first['incident_id'] and third['corroboration_count']==3 and third['status']=='corroborated'
        as_user(0)
        assert conn.execute(QUERY,args).fetchone()[0]['status']=='corroborated'
        assert conn.execute('SELECT count(*) FROM trujillo.reports WHERE incident_id=%s',(first['incident_id'],)).fetchone()[0]==1
        distant,_=send(3,lat=-59.998)
        different,_=send(3,category='Auxilio')
        late,_=send(3,offset=901)
        for result in (distant,different,late): assert result['incident_id']!=first['incident_id']
        boundary,_=send(4,offset=900)
        assert boundary['incident_id']==first['incident_id']
        anchor,_=send(0,lng=-130)
        nearby,_=send(1,lat=-59.9993,lng=-130,offset=10)
        chain,_=send(2,lat=-59.9986,lng=-130,offset=20)
        assert nearby['incident_id']==anchor['incident_id'] and chain['incident_id']!=anchor['incident_id']
        left,_=send(0,lng=-120)
        right,_=send(1,lat=-59.9985,lng=-120)
        middle,_=send(2,lat=-59.99925,lng=-120,offset=1)
        assert middle['needs_review'] and middle['status']=='pending'
        assert middle['incident_id'] not in (left['incident_id'],right['incident_id'])
        print('OK: tres cuentas, reintentos, privacidad, radio, tiempo, punto fijo y ambigüedad.')
    finally:
        conn.rollback()
