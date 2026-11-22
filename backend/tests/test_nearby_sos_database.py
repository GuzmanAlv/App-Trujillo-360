from uuid import uuid4
import psycopg
import pytest
from psycopg.types.json import Jsonb
from test_sos_cases_database import database


def test_nearby_sos_includes_own_and_others_but_not_legacy_private_or_expired(database):
    owner,other,operator=[uuid4() for _ in range(3)]
    with psycopg.connect(database) as c:
        for uid,role in [(owner,'citizen'),(other,'citizen'),(operator,'operator')]:
            c.execute("INSERT INTO trujillo.users(id,auth_provider,auth_subject,display_name,role) VALUES(%s,'firebase',%s,'Test',%s)",(uid,str(uid),role))
        legacy=c.execute("INSERT INTO trujillo.incidents(category,location,occurred_at,status,was_public) VALUES('Robo',extensions.ST_SetSRID(extensions.ST_MakePoint(-79,-8.1),4326)::extensions.geography,now(),'verified',true) RETURNING id").fetchone()[0]
    def query(uid,sql,args=()):
        with psycopg.connect(database) as c:
            c.execute("SELECT set_config('app.firebase_uid',%s,true)",(str(uid),))
            c.execute('SET LOCAL ROLE trujillo_api')
            return [r[0] for r in c.execute(sql,args)]
    def case(uid,lat,action=None):
        sos=query(uid,'SELECT trujillo.submit_sos(%s,%s,-79)',(uuid4(),lat))[0]['id']
        data=dict(action='confirm',category='Auxilio',latitude=lat,longitude=-79,place='',public_description='',outcome='',internal_note='PRIVATE OPERATOR NOTE')
        confirmed=query(operator,'SELECT trujillo.sos_case_update(%s,%s,0,%s)',(sos,uuid4(),Jsonb(data)))[0]
        if action:
            query(operator,'SELECT trujillo.sos_case_update(%s,%s,1,%s)',(sos,uuid4(),Jsonb({**data,'action':action,'outcome':'Atención finalizada'})))
        return confirmed['incident_id']
    own=case(owner,-8.1)
    foreign=case(other,-8.103)
    resolved=case(other,-8.105,'resolve')
    case(other,-8.12)
    case(other,-8.101,'discard')
    query(other,'SELECT trujillo.submit_sos(%s,-8.1,-79)',(uuid4(),))
    for reader in (owner,other,operator):
        rows=query(reader,'SELECT trujillo.nearby_sos(-8.1,-79)')
        assert {r['id'] for r in rows}=={own,foreign,resolved}
        assert all(r['is_sos'] is True for r in rows)
        assert str(legacy) not in str(rows) and 'PRIVATE OPERATOR NOTE' not in str(rows)
        assert all('user_id' not in r and 'caller_latitude' not in r and 'operator_id' not in r for r in rows)
        assert next(r for r in rows if r['id']==resolved)['attention']=='resolved'
    with psycopg.connect(database) as c:
        c.execute('ALTER TABLE trujillo.incidents DISABLE TRIGGER track_incident_resolution')
        c.execute("UPDATE trujillo.incidents SET resolved_at=now()-interval '7 days' WHERE id=%s",(resolved,))
        c.execute('ALTER TABLE trujillo.incidents ENABLE TRIGGER track_incident_resolution')
    assert {r['id'] for r in query(owner,'SELECT trujillo.nearby_sos(-8.1,-79)')}=={own,foreign}
    with pytest.raises(psycopg.errors.InsufficientPrivilege):query(uuid4(),'SELECT trujillo.nearby_sos(-8.1,-79)')
    with pytest.raises(psycopg.errors.InvalidParameterValue):query(owner,'SELECT trujillo.nearby_sos(91,-79)')
