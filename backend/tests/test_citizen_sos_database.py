from uuid import uuid4
import base64
import io
from PIL import Image
import psycopg
import pytest
from psycopg.types.json import Jsonb
from test_sos_cases_database import database
from app.photos import PhotoInput, normalize_photo

def test_owner_follow_up_privacy_photos_and_idempotency(database):
    citizen,other,operator=[uuid4() for _ in range(3)]
    with psycopg.connect(database) as c:
        for uid,role in [(citizen,'citizen'),(other,'citizen'),(operator,'operator')]:
            c.execute("INSERT INTO trujillo.users(id,auth_provider,auth_subject,display_name,role) VALUES(%s,'firebase',%s,'Test',%s)",(uid,str(uid),role))
    def query(uid,sql,args=(),many=False):
        with psycopg.connect(database) as c:
            c.execute("SELECT set_config('app.firebase_uid',%s,true)",(str(uid),))
            c.execute('SET LOCAL ROLE trujillo_api')
            cur=c.execute(sql,args)
            return cur.fetchall() if many else cur.fetchone()[0]
    case=query(citizen,'SELECT trujillo.submit_sos(%s,-8,-79)',(uuid4(),))['id']
    query(citizen,"SELECT trujillo.call_action(%s,'start')",(case,))
    query(operator,"SELECT trujillo.call_action(%s,'accept')",(case,))
    query(operator,"SELECT trujillo.call_action(%s,'end')",(case,))
    assert query(operator,'SELECT trujillo.sos_case_read(%s)',(case,))['decision']=='pending'
    assert query(citizen,'SELECT trujillo.citizen_sos_cases()',many=True)==[]
    with pytest.raises(psycopg.errors.InvalidParameterValue):query(citizen,'SELECT trujillo.sos_citizen_submit(%s,%s,%s,%s)',(case,uuid4(),'Antes de verificar',Jsonb([])))
    data=dict(action='confirm',category='Robo',latitude=-8.12,longitude=-79.02,place='',public_description='',internal_note='NO PUBLICAR',outcome='')
    result=query(operator,'SELECT trujillo.sos_case_update(%s,%s,0,%s)',(case,uuid4(),Jsonb(data)))
    own=query(citizen,'SELECT trujillo.citizen_sos_cases()')
    assert own['id']==case and own['attention']=='none'
    assert 'NO PUBLICAR' not in str(own)
    assert query(other,'SELECT trujillo.citizen_sos_cases()',many=True)==[]
    with pytest.raises(psycopg.errors.InsufficientPrivilege):query(other,'SELECT trujillo.sos_citizen_evidence(%s)',(case,))
    with pytest.raises(psycopg.errors.InsufficientPrivilege):query(other,'SELECT trujillo.sos_citizen_submit(%s,%s,%s,%s)',(case,uuid4(),'Otro usuario',Jsonb([])))
    raw=io.BytesIO();Image.new('RGB',(8,8),'red').save(raw,format='PNG')
    photo=normalize_photo(PhotoInput(id=uuid4(),content_base64=base64.b64encode(raw.getvalue()).decode()))
    request=uuid4()
    args=(case,request,'Aporte privado',Jsonb([photo]))
    assert query(citizen,'SELECT trujillo.sos_citizen_submit(%s,%s,%s,%s)',args)['id']==str(request)
    query(citizen,'SELECT trujillo.sos_citizen_submit(%s,%s,%s,%s)',args)
    posts=query(operator,'SELECT trujillo.sos_citizen_evidence(%s)',(case,),many=True)
    assert len(posts)==1 and posts[0][0]['description']=='Aporte privado'
    assert 'content_base64' not in str(posts)
    content=query(operator,'SELECT trujillo.sos_citizen_photo(%s,%s)',(case,photo['id']))
    assert bytes(content)==base64.b64decode(photo['content_base64'])
    with pytest.raises(psycopg.errors.InsufficientPrivilege):query(other,'SELECT trujillo.sos_citizen_photo(%s,%s)',(case,photo['id']))
    with pytest.raises(psycopg.errors.RaiseException):query(citizen,'SELECT trujillo.sos_citizen_submit(%s,%s,%s,%s)',(case,request,'Cambio',Jsonb([photo])))
    public=query(other,'SELECT trujillo.public_case_fields(%s::uuid[])',([result['incident_id']],))
    assert 'Aporte privado' not in str(public)
    for action,version in [('en_route',1),('on_scene',2),('resolve',3)]:
        query(operator,'SELECT trujillo.sos_case_update(%s,%s,%s,%s)',(case,uuid4(),version,Jsonb({**data,'action':action,'outcome':'Atención concluida'})))
        if action!='resolve':assert query(citizen,'SELECT trujillo.citizen_sos_cases()')['attention']==action
    assert query(citizen,'SELECT trujillo.citizen_sos_cases()',many=True)==[]
    assert query(citizen,'SELECT trujillo.citizen_sos_cases(%s)',(case,))['attention']=='resolved'
    with psycopg.connect(database) as c:
        assert c.execute('SELECT count(*) FROM trujillo.incidents').fetchone()[0]==1
        assert c.execute('SELECT count(*) FROM trujillo.reports').fetchone()[0]==0
        c.execute('SET LOCAL ROLE trujillo_api')
        with pytest.raises(psycopg.errors.InsufficientPrivilege):c.execute('SELECT * FROM trujillo.sos_citizen_updates')
