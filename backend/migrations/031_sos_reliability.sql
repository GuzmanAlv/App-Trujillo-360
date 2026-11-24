ALTER TABLE trujillo.sos_cases ALTER COLUMN operator_id DROP NOT NULL;
ALTER TABLE trujillo.sos_cases ADD COLUMN claim_expires_at timestamptz;
UPDATE trujillo.sos_cases SET claim_expires_at=now()+interval '2 minutes' WHERE decision='pending';

CREATE FUNCTION trujillo.expire_sos_claims() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c trujillo.sos_cases;
BEGIN
 PERFORM pg_advisory_xact_lock(360017);
 FOR c IN SELECT * FROM trujillo.sos_cases WHERE decision='pending' AND operator_id IS NOT NULL AND claim_expires_at<=now() FOR UPDATE LOOP
  INSERT INTO trujillo.sos_case_events(case_id,actor_id,request_id,payload,snapshot)
   VALUES(c.id,c.operator_id,gen_random_uuid(),'{"action":"claim_expired"}'::jsonb,to_jsonb(c));
  UPDATE trujillo.sos_cases SET operator_id=NULL,claim_expires_at=NULL,version=version+1 WHERE id=c.id;
  UPDATE trujillo.call_sessions SET state='ended',ended_at=coalesce(ended_at,now()),operator_id=NULL
   WHERE id=c.id AND operator_id=c.operator_id;
  UPDATE trujillo.help_requests SET stage='Recibida' WHERE id=c.id AND stage='En revisión';
 END LOOP;
END; $$;

CREATE FUNCTION trujillo.renew_sos_claim(p_id uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid;
BEGIN
 actor:=trujillo.current_actor(true);
 PERFORM trujillo.expire_sos_claims();
 UPDATE trujillo.sos_cases SET claim_expires_at=now()+interval '2 minutes'
 WHERE id=p_id AND operator_id=actor AND decision='pending';
 RETURN FOUND;
END; $$;

ALTER FUNCTION trujillo.claim_sos(uuid) RENAME TO claim_sos_v30;
CREATE FUNCTION trujillo.claim_sos(p_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid;
BEGIN
 actor:=trujillo.current_actor(true);
 PERFORM trujillo.expire_sos_claims();
 IF EXISTS(SELECT 1 FROM trujillo.sos_cases WHERE operator_id=actor AND id<>p_id
   AND ((decision='pending' AND claim_expires_at>now()) OR
        (decision='confirmed' AND attention IN ('en_route','on_scene')))) THEN
  RAISE EXCEPTION 'Operador ocupado' USING ERRCODE='P0001';
 END IF;
 PERFORM trujillo.claim_sos_v30(p_id);
 UPDATE trujillo.sos_cases SET operator_id=actor,claim_expires_at=now()+interval '2 minutes'
 WHERE id=p_id AND decision='pending' AND (operator_id IS NULL OR operator_id=actor);
 RETURN trujillo.sos_case_read(p_id);
END; $$;

ALTER FUNCTION trujillo.list_help(boolean) RENAME TO list_help_v30;
CREATE FUNCTION trujillo.list_help(p_operator boolean DEFAULT false) RETURNS SETOF jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid;
BEGIN
 actor:=trujillo.current_actor(p_operator);
 IF p_operator THEN
  PERFORM trujillo.expire_sos_claims();
  UPDATE trujillo.sos_cases SET claim_expires_at=now()+interval '2 minutes'
   WHERE operator_id=actor AND decision='pending';
 END IF;
 RETURN QUERY SELECT * FROM trujillo.list_help_v30(p_operator);
END; $$;

ALTER FUNCTION trujillo.sos_case_read(uuid) RENAME TO sos_case_read_v30;
CREATE FUNCTION trujillo.sos_case_read(p_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM trujillo.renew_sos_claim(p_id);
 RETURN trujillo.sos_case_read_v30(p_id);
END; $$;

ALTER FUNCTION trujillo.sos_case_update(uuid,uuid,integer,jsonb) RENAME TO sos_case_update_v30;
CREATE FUNCTION trujillo.sos_case_update(p_id uuid,p_request uuid,p_version integer,p_data jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM trujillo.renew_sos_claim(p_id);
 IF EXISTS(SELECT 1 FROM trujillo.sos_cases WHERE id=p_id AND decision='pending' AND operator_id IS NULL) THEN
  RAISE EXCEPTION 'Debes aceptar nuevamente el SOS' USING ERRCODE='42501';
 END IF;
 RETURN trujillo.sos_case_update_v30(p_id,p_request,p_version,p_data);
END; $$;

ALTER FUNCTION trujillo.call_action(uuid,text) RENAME TO call_action_v30;
CREATE FUNCTION trujillo.call_action(p_id uuid,p_action text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM trujillo.current_actor(false);
 PERFORM trujillo.expire_sos_claims();
 IF EXISTS(SELECT 1 FROM trujillo.users WHERE id=trujillo.current_actor(false) AND role IN ('operator','admin')) THEN
  IF p_action='accept' THEN PERFORM trujillo.claim_sos(p_id); END IF;
  PERFORM trujillo.renew_sos_claim(p_id);
 END IF;
 RETURN trujillo.call_action_v30(p_id,p_action);
END; $$;

REVOKE ALL ON FUNCTION trujillo.expire_sos_claims(),trujillo.renew_sos_claim(uuid),
 trujillo.claim_sos_v30(uuid),trujillo.list_help_v30(boolean),trujillo.sos_case_read_v30(uuid),
 trujillo.sos_case_update_v30(uuid,uuid,integer,jsonb),trujillo.call_action_v30(uuid,text)
 FROM PUBLIC,anon,authenticated,trujillo_api;
REVOKE ALL ON FUNCTION trujillo.claim_sos(uuid),trujillo.list_help(boolean),trujillo.sos_case_read(uuid),
 trujillo.sos_case_update(uuid,uuid,integer,jsonb),trujillo.call_action(uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION trujillo.claim_sos(uuid),trujillo.list_help(boolean),trujillo.sos_case_read(uuid),
 trujillo.sos_case_update(uuid,uuid,integer,jsonb),trujillo.call_action(uuid,text),trujillo.renew_sos_claim(uuid) TO trujillo_api;

CREATE FUNCTION trujillo.release_sos_claim(p_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; c trujillo.sos_cases;
BEGIN
 actor:=trujillo.current_actor(true);
 PERFORM trujillo.expire_sos_claims();
 SELECT * INTO c FROM trujillo.sos_cases WHERE id=p_id FOR UPDATE;
 IF c.id IS NULL OR c.operator_id IS DISTINCT FROM actor OR c.decision<>'pending' THEN
  RAISE EXCEPTION 'Reserva no disponible' USING ERRCODE='42501';
 END IF;
 INSERT INTO trujillo.sos_case_events(case_id,actor_id,request_id,payload,snapshot)
 VALUES(c.id,actor,gen_random_uuid(),'{"action":"claim_released"}'::jsonb,to_jsonb(c));
 UPDATE trujillo.sos_cases SET operator_id=NULL,claim_expires_at=NULL,version=version+1 WHERE id=c.id;
 UPDATE trujillo.call_sessions SET state='ended',ended_at=coalesce(ended_at,now()),operator_id=NULL WHERE id=c.id;
 UPDATE trujillo.help_requests SET stage='Recibida' WHERE id=c.id AND stage='En revisión';
END; $$;
REVOKE ALL ON FUNCTION trujillo.release_sos_claim(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION trujillo.release_sos_claim(uuid) TO trujillo_api;
