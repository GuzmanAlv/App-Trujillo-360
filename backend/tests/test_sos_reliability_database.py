from uuid import uuid4
import psycopg
import pytest
from test_sos_cases_database import database


def test_expired_reservation_can_be_recovered_and_pending_reservations_are_bounded(database):
    citizen, first, second = [uuid4() for _ in range(3)]
    with psycopg.connect(database) as c:
        for uid, role in [(citizen,'citizen'),(first,'operator'),(second,'operator')]:
            c.execute("INSERT INTO trujillo.users(id,auth_provider,auth_subject,display_name,role) VALUES(%s,'firebase',%s,'Test',%s)",(uid,str(uid),role))
    def query(uid,sql,args=()):
        with psycopg.connect(database) as c:
            c.execute("SELECT set_config('app.firebase_uid',%s,true)",(str(uid),))
            c.execute('SET LOCAL ROLE trujillo_api')
            return c.execute(sql,args).fetchall()
    case=query(citizen,'SELECT trujillo.submit_sos(%s,-8,-79)',(uuid4(),))[0][0]['id']
    another=query(citizen,'SELECT trujillo.submit_sos(%s,-8,-79)',(uuid4(),))[0][0]['id']
    query(citizen,"SELECT trujillo.call_action(%s,'start')",(case,))
    query(first,'SELECT trujillo.claim_sos(%s)',(case,))
    query(first,"SELECT trujillo.call_action(%s,'accept')",(case,))
    with pytest.raises(psycopg.errors.RaiseException):query(second,'SELECT trujillo.claim_sos(%s)',(case,))
    with pytest.raises(psycopg.errors.RaiseException):query(first,'SELECT trujillo.claim_sos(%s)',(another,))
    assert query(first,'SELECT trujillo.renew_sos_claim(%s)',(case,))[0][0] is True
    with psycopg.connect(database) as c:
        c.execute("UPDATE trujillo.sos_cases SET claim_expires_at=now()-interval '1 second' WHERE id=%s",(case,))
    query(second,'SELECT trujillo.list_help(true)')
    assert query(second,'SELECT trujillo.sos_offer_status(%s)',(case,))[0][0]['available'] is True
    with pytest.raises(psycopg.errors.InsufficientPrivilege):query(first,"SELECT trujillo.call_action(%s,'token')",(case,))
    query(second,'SELECT trujillo.claim_sos(%s)',(case,))
    with pytest.raises(psycopg.errors.InsufficientPrivilege):query(first,'SELECT trujillo.release_sos_claim(%s)',(case,))
    query(second,'SELECT trujillo.release_sos_claim(%s)',(case,))
    assert query(first,'SELECT trujillo.sos_offer_status(%s)',(case,))[0][0]['available'] is True
    query(first,'SELECT trujillo.claim_sos(%s)',(case,))
    assert query(first,'SELECT trujillo.sos_case_read(%s)',(case,))[0][0]['can_edit'] is True
    # Reading another operator's case must not renew their reservation.
    with psycopg.connect(database) as c:
        before=c.execute('SELECT claim_expires_at FROM trujillo.sos_cases WHERE id=%s',(case,)).fetchone()[0]
    query(second,'SELECT trujillo.sos_case_read(%s)',(case,))
    with psycopg.connect(database) as c:
        assert c.execute('SELECT claim_expires_at FROM trujillo.sos_cases WHERE id=%s',(case,)).fetchone()[0]==before
    with psycopg.connect(database) as c:
        actions=[r[0] for r in c.execute("SELECT payload->>'action' FROM trujillo.sos_case_events WHERE case_id=%s",(case,))]
        assert 'claim_expired' in actions and 'claim_released' in actions
