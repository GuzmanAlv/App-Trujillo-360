CREATE TABLE trujillo.operator_availability(
 user_id uuid PRIMARY KEY REFERENCES trujillo.users(id),
 online boolean NOT NULL DEFAULT true,last_seen timestamptz NOT NULL DEFAULT now(),
 can_accept_transfers boolean NOT NULL DEFAULT false
);
INSERT INTO trujillo.operator_availability(user_id)
 SELECT id FROM trujillo.users WHERE role IN ('operator','admin') AND status='active';
CREATE TABLE trujillo.sos_dispatch(
 case_id uuid PRIMARY KEY REFERENCES trujillo.sos_cases(id),
 state text NOT NULL CHECK(state IN ('assigned','searching','offered')),
 generation uuid NOT NULL DEFAULT gen_random_uuid(),offer_expires_at timestamptz,
 updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO trujillo.sos_dispatch(case_id,state)
 SELECT id,CASE WHEN operator_id IS NULL THEN 'searching' ELSE 'assigned' END
 FROM trujillo.sos_cases WHERE decision='confirmed' AND attention IN ('en_route','on_scene');
CREATE TABLE trujillo.sos_dispatch_exclusions(
 case_id uuid NOT NULL REFERENCES trujillo.sos_cases(id),operator_id uuid NOT NULL REFERENCES trujillo.users(id),
 until_at timestamptz NOT NULL,PRIMARY KEY(case_id,operator_id)
);
CREATE TABLE trujillo.sos_dispatch_events(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,case_id uuid NOT NULL REFERENCES trujillo.sos_cases(id),
 previous_operator uuid,operator_id uuid,reason text NOT NULL,created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE trujillo.sos_contact_requests(
 case_id uuid PRIMARY KEY REFERENCES trujillo.help_requests(id),expires_at timestamptz NOT NULL
);
CREATE TABLE trujillo.sos_rate_events(
 actor_id uuid NOT NULL REFERENCES trujillo.users(id),kind text NOT NULL,created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX sos_rate_actor ON trujillo.sos_rate_events(actor_id,kind,created_at);
CREATE TABLE trujillo.sos_room_cleanup(
 room text PRIMARY KEY,attempts integer NOT NULL DEFAULT 0,next_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE trujillo.sos_escalation(
 case_id uuid PRIMARY KEY REFERENCES trujillo.help_requests(id),level integer NOT NULL CHECK(level BETWEEN 0 AND 3)
);
ALTER TABLE trujillo.operator_availability ENABLE ROW LEVEL SECURITY;
ALTER TABLE trujillo.sos_dispatch ENABLE ROW LEVEL SECURITY;
ALTER TABLE trujillo.sos_dispatch_exclusions ENABLE ROW LEVEL SECURITY;
ALTER TABLE trujillo.sos_dispatch_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE trujillo.sos_contact_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE trujillo.sos_rate_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE trujillo.sos_room_cleanup ENABLE ROW LEVEL SECURITY;
ALTER TABLE trujillo.sos_escalation ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON trujillo.operator_availability,trujillo.sos_dispatch,trujillo.sos_dispatch_exclusions,
 trujillo.sos_dispatch_events,trujillo.sos_contact_requests,trujillo.sos_rate_events,trujillo.sos_room_cleanup,
 trujillo.sos_escalation FROM PUBLIC,anon,authenticated,trujillo_api;

CREATE FUNCTION trujillo.operator_heartbeat(p_online boolean DEFAULT true) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid;
BEGIN
 actor:=trujillo.current_actor(true);
 INSERT INTO trujillo.operator_availability(user_id,online,last_seen) VALUES(actor,p_online,now())
 ON CONFLICT(user_id) DO UPDATE SET online=CASE WHEN NOT p_online THEN false ELSE operator_availability.online END,last_seen=now();
 RETURN jsonb_build_object('online',(SELECT online FROM trujillo.operator_availability WHERE user_id=actor));
END; $$;
CREATE FUNCTION trujillo.operator_begin_duty() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid;
BEGIN
 actor:=trujillo.current_actor(true);
 INSERT INTO trujillo.operator_availability VALUES(actor,true,now(),true)
 ON CONFLICT(user_id) DO UPDATE SET online=true,last_seen=now(),can_accept_transfers=true;
 RETURN jsonb_build_object('online',true);
END; $$;
ALTER FUNCTION trujillo.operator_position(double precision,double precision,double precision,timestamptz) RENAME TO operator_position_v33;
CREATE FUNCTION trujillo.operator_position(p_lat double precision,p_lng double precision,p_accuracy double precision,p_observed timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb;
BEGIN
 result:=trujillo.operator_position_v33(p_lat,p_lng,p_accuracy,p_observed);
 PERFORM trujillo.operator_heartbeat(true);
 RETURN result;
END; $$;

CREATE FUNCTION trujillo.sos_rate_allow(p_actor uuid,p_kind text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('sos-rate:'||p_actor::text,0));
 IF p_kind='create' THEN
  IF (SELECT count(*) FROM trujillo.sos_rate_events WHERE actor_id=p_actor AND kind=p_kind AND created_at>now()-interval '10 minutes')>=3
   OR (SELECT count(*) FROM trujillo.sos_rate_events WHERE actor_id=p_actor AND kind=p_kind AND created_at>now()-interval '1 hour')>=10 THEN RETURN false; END IF;
 ELSE
  IF EXISTS(SELECT 1 FROM trujillo.sos_rate_events WHERE actor_id=p_actor AND kind=p_kind AND created_at>now()-interval '15 seconds')
   OR (SELECT count(*) FROM trujillo.sos_rate_events WHERE actor_id=p_actor AND kind=p_kind AND created_at>now()-interval '5 minutes')>=6 THEN RETURN false; END IF;
 END IF;
 INSERT INTO trujillo.sos_rate_events(actor_id,kind) VALUES(p_actor,p_kind);
 RETURN true;
END; $$;

ALTER FUNCTION trujillo.submit_sos(uuid,double precision,double precision) RENAME TO submit_sos_v33;
CREATE FUNCTION trujillo.submit_sos(p_request uuid,p_lat double precision,p_lng double precision) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; h trujillo.help_requests;
BEGIN
 actor:=trujillo.current_actor(false);
 PERFORM pg_advisory_xact_lock(360017);
 IF EXISTS(SELECT 1 FROM trujillo.help_requests WHERE user_id=actor AND request_id=p_request) THEN
  RETURN trujillo.submit_sos_v33(p_request,p_lat,p_lng);
 END IF;
 SELECT * INTO h FROM trujillo.help_requests WHERE user_id=actor AND source='sos'
 AND stage NOT IN ('Cerrada','Descartada') ORDER BY received_at,id LIMIT 1;
 IF FOUND THEN RETURN (to_jsonb(h)-'user_id')||jsonb_build_object('existing_active',true); END IF;
 IF NOT trujillo.sos_rate_allow(actor,'create') THEN
  RETURN jsonb_build_object('error_code','SOS_RATE_LIMIT','retry_after',600); END IF;
 RETURN trujillo.submit_sos_v33(p_request,p_lat,p_lng);
END; $$;

CREATE OR REPLACE FUNCTION trujillo.operator_in_sos_zone(p_actor uuid,p_case uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM trujillo.sos_cases c JOIN trujillo.sos_dispatch d ON d.case_id=c.id
 WHERE c.id=p_case AND c.operator_id=p_actor AND d.state='offered' AND d.offer_expires_at>now())
 OR EXISTS(SELECT 1 FROM trujillo.operator_presence p JOIN trujillo.help_requests h ON h.id=p_case
 WHERE p.user_id=p_actor AND p.observed_at>now()-interval '10 minutes' AND h.source='sos'
 AND EXISTS(SELECT 1 FROM trujillo.operator_availability a WHERE a.user_id=p_actor AND a.online AND a.last_seen>now()-interval '120 seconds')
 AND (coalesce((SELECT level FROM trujillo.sos_escalation WHERE case_id=p_case),0)=3 OR extensions.ST_DWithin(
 extensions.ST_SetSRID(extensions.ST_MakePoint(p.longitude,p.latitude),4326)::extensions.geography,
 extensions.ST_SetSRID(extensions.ST_MakePoint(h.longitude,h.latitude),4326)::extensions.geography,
 CASE coalesce((SELECT level FROM trujillo.sos_escalation WHERE case_id=p_case),0) WHEN 0 THEN 15000 WHEN 1 THEN 30000 ELSE 60000 END)));
$$;

CREATE FUNCTION trujillo.sos_end_audio(p_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 INSERT INTO trujillo.sos_contact_requests(case_id,expires_at)
 SELECT id,now()+interval '90 seconds' FROM trujillo.call_sessions WHERE id=p_id AND state IN ('waiting','accepted') AND expires_at>now()
 ON CONFLICT(case_id) DO UPDATE SET expires_at=greatest(sos_contact_requests.expires_at,EXCLUDED.expires_at);
 INSERT INTO trujillo.sos_room_cleanup(room)
 SELECT 'sos-'||id::text||'-'||generation::text FROM trujillo.call_sessions WHERE id=p_id AND state IN ('waiting','accepted')
 ON CONFLICT(room) DO NOTHING;
 UPDATE trujillo.call_sessions SET state='ended',ended_at=coalesce(ended_at,now()),operator_id=NULL WHERE id=p_id;
END; $$;

CREATE FUNCTION trujillo.sos_dispatch_tick() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c trujillo.sos_cases; d trujillo.sos_dispatch; h record; next_op uuid; old_op uuid; new_level integer;
BEGIN
 IF NOT pg_try_advisory_xact_lock(360017) THEN RETURN '{}'::jsonb; END IF;
 PERFORM trujillo.expire_sos_claims();
 FOR h IN SELECT r.* FROM trujillo.help_requests r LEFT JOIN trujillo.sos_cases s ON s.id=r.id
 WHERE r.source='sos' AND r.stage NOT IN ('Cerrada','Descartada') AND coalesce(s.decision,'pending')='pending'
 AND coalesce(s.operator_id,(SELECT operator_id FROM trujillo.call_sessions WHERE id=r.id)) IS NULL LOOP
  new_level:=CASE WHEN now()-h.received_at>=interval '120 seconds' THEN 3 WHEN now()-h.received_at>=interval '60 seconds' THEN 2
   WHEN now()-h.received_at>=interval '30 seconds' THEN 1 ELSE 0 END;
  IF new_level>coalesce((SELECT level FROM trujillo.sos_escalation WHERE case_id=h.id),0) THEN
   INSERT INTO trujillo.sos_escalation VALUES(h.id,new_level) ON CONFLICT(case_id) DO UPDATE SET level=new_level;
   INSERT INTO trujillo.push_outbox(device_id,user_id,event_key,kind,target_id,expires_at)
   SELECT p.id,p.user_id,'escalation:'||h.id::text||':'||new_level::text,'operator',h.id,now()+interval '2 minutes'
   FROM trujillo.push_devices p JOIN trujillo.users u ON u.id=p.user_id
   WHERE p.operator_enabled AND u.status='active' AND u.role IN ('operator','admin')
   AND trujillo.operator_in_sos_zone(u.id,h.id) ON CONFLICT(device_id,event_key) DO NOTHING;
  END IF;
 END LOOP;
 FOR c IN SELECT * FROM trujillo.sos_cases WHERE decision='confirmed' AND attention IN ('en_route','on_scene') ORDER BY updated_at,id LOOP
  INSERT INTO trujillo.sos_dispatch(case_id,state) VALUES(c.id,'assigned') ON CONFLICT(case_id) DO NOTHING;
  SELECT * INTO d FROM trujillo.sos_dispatch WHERE case_id=c.id;
  IF d.state='assigned' AND EXISTS(SELECT 1 FROM trujillo.operator_availability a JOIN trujillo.users u ON u.id=a.user_id
   WHERE a.user_id=c.operator_id AND a.online AND a.last_seen>now()-interval '120 seconds' AND u.status='active') THEN CONTINUE; END IF;
  IF d.state='offered' AND d.offer_expires_at>now() AND EXISTS(SELECT 1 FROM trujillo.operator_availability a JOIN trujillo.users u ON u.id=a.user_id
   WHERE a.user_id=c.operator_id AND a.online AND a.last_seen>now()-interval '120 seconds' AND u.status='active') THEN CONTINUE; END IF;
  old_op:=c.operator_id;
  IF old_op IS NOT NULL THEN
   INSERT INTO trujillo.sos_dispatch_exclusions VALUES(c.id,old_op,now()+interval '5 minutes')
   ON CONFLICT(case_id,operator_id) DO UPDATE SET until_at=EXCLUDED.until_at;
   PERFORM trujillo.sos_end_audio(c.id);
   DELETE FROM trujillo.sos_arrival_samples WHERE case_id=c.id;
  END IF;
  SELECT p.user_id INTO next_op FROM trujillo.operator_presence p JOIN trujillo.operator_availability a ON a.user_id=p.user_id
  JOIN trujillo.users u ON u.id=p.user_id
  WHERE u.status='active' AND u.role IN ('operator','admin') AND a.online AND a.can_accept_transfers AND a.last_seen>now()-interval '90 seconds'
  AND p.user_id<>(SELECT user_id FROM trujillo.help_requests WHERE id=c.id)
  AND p.observed_at>now()-interval '120 seconds'
  AND NOT EXISTS(SELECT 1 FROM trujillo.sos_dispatch_exclusions e WHERE e.case_id=c.id AND e.operator_id=p.user_id AND e.until_at>now())
  AND NOT EXISTS(SELECT 1 FROM trujillo.sos_cases busy WHERE busy.operator_id=p.user_id AND busy.id<>c.id
   AND ((busy.decision='confirmed' AND busy.attention IN ('en_route','on_scene')) OR (busy.decision='pending' AND busy.claim_expires_at>now())))
  AND NOT EXISTS(SELECT 1 FROM trujillo.call_sessions s WHERE s.id<>c.id AND s.state IN ('waiting','accepted') AND s.expires_at>now()
   AND (s.operator_id=p.user_id OR s.citizen_id=p.user_id))
  ORDER BY extensions.ST_Distance(extensions.ST_SetSRID(extensions.ST_MakePoint(p.longitude,p.latitude),4326)::extensions.geography,
   extensions.ST_SetSRID(extensions.ST_MakePoint(
    coalesce((SELECT longitude FROM trujillo.sos_live_positions WHERE case_id=c.id AND observed_at>now()-interval '60 seconds'),c.longitude),
    coalesce((SELECT latitude FROM trujillo.sos_live_positions WHERE case_id=c.id AND observed_at>now()-interval '60 seconds'),c.latitude)),4326)::extensions.geography),p.user_id LIMIT 1;
  IF old_op IS NULL AND next_op IS NULL AND d.state='searching' THEN CONTINUE; END IF;
  UPDATE trujillo.sos_cases SET operator_id=next_op,attention='en_route',version=version+1,updated_at=now() WHERE id=c.id;
  UPDATE trujillo.incidents SET attention='none',updated_at=now() WHERE id=c.incident_id;
  UPDATE trujillo.sos_dispatch SET state=CASE WHEN next_op IS NULL THEN 'searching' ELSE 'offered' END,
   generation=gen_random_uuid(),offer_expires_at=CASE WHEN next_op IS NULL THEN NULL ELSE now()+interval '45 seconds' END,updated_at=now()
   WHERE case_id=c.id RETURNING * INTO d;
  IF old_op IS NOT NULL OR next_op IS NOT NULL THEN
   INSERT INTO trujillo.sos_dispatch_events(case_id,previous_operator,operator_id,reason)
   VALUES(c.id,old_op,next_op,CASE WHEN old_op IS NULL THEN 'operator_offer' ELSE 'operator_unavailable' END);
  END IF;
  IF next_op IS NOT NULL THEN
   INSERT INTO trujillo.push_outbox(device_id,user_id,event_key,kind,target_id,expires_at)
   SELECT p.id,p.user_id,'assignment:'||c.id::text||':'||d.generation::text,'operator',c.id,d.offer_expires_at
   FROM trujillo.push_devices p WHERE p.user_id=next_op AND p.operator_enabled ON CONFLICT(device_id,event_key) DO NOTHING;
  END IF;
 END LOOP;
 DELETE FROM trujillo.sos_rate_events WHERE created_at<now()-interval '1 day';
 RETURN jsonb_build_object('status','ok');
END; $$;

CREATE FUNCTION trujillo.sos_open_audio(p_id uuid,p_operator uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 INSERT INTO trujillo.call_sessions(id,citizen_id,operator_id)
 SELECT id,user_id,p_operator FROM trujillo.help_requests WHERE id=p_id
 ON CONFLICT(id) DO UPDATE SET direction='citizen',generation=gen_random_uuid(),state='waiting',
 operator_id=p_operator,created_at=now(),accepted_at=NULL,ended_at=NULL,expires_at=now()+interval '90 seconds';
 IF p_operator IS NOT NULL THEN
  INSERT INTO trujillo.push_outbox(device_id,user_id,event_key,kind,target_id,expires_at)
  SELECT d.id,d.user_id,'redial:'||p_id::text||':'||s.generation::text,'operator',p_id,s.expires_at
  FROM trujillo.push_devices d CROSS JOIN trujillo.call_sessions s WHERE s.id=p_id AND d.user_id=p_operator AND d.operator_enabled
  ON CONFLICT(device_id,event_key) DO NOTHING;
 END IF;
END; $$;

ALTER FUNCTION trujillo.claim_sos(uuid) RENAME TO claim_sos_v33;
CREATE FUNCTION trujillo.claim_sos(p_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; c trujillo.sos_cases; d trujillo.sos_dispatch;
BEGIN
 actor:=trujillo.current_actor(true);
 PERFORM pg_advisory_xact_lock(360017);
 SELECT * INTO c FROM trujillo.sos_cases WHERE id=p_id;
 SELECT * INTO d FROM trujillo.sos_dispatch WHERE case_id=p_id;
 IF d.state='offered' THEN
  IF c.operator_id IS DISTINCT FROM actor OR d.offer_expires_at<=now() THEN RAISE EXCEPTION 'Oferta no disponible' USING ERRCODE='42501'; END IF;
  IF EXISTS(SELECT 1 FROM trujillo.sos_cases WHERE id<>p_id AND operator_id=actor
   AND ((decision='confirmed' AND attention IN ('en_route','on_scene')) OR (decision='pending' AND claim_expires_at>now())))
   OR EXISTS(SELECT 1 FROM trujillo.call_sessions WHERE id<>p_id AND state IN ('waiting','accepted') AND expires_at>now()
    AND (operator_id=actor OR citizen_id=actor)) THEN RAISE EXCEPTION 'Operador ocupado'; END IF;
  UPDATE trujillo.sos_dispatch SET state='assigned',offer_expires_at=NULL,updated_at=now() WHERE case_id=p_id;
  UPDATE trujillo.sos_cases SET version=version+1,updated_at=now() WHERE id=p_id;
  UPDATE trujillo.incidents SET attention='en_route',updated_at=now() WHERE id=c.incident_id;
  PERFORM trujillo.operator_heartbeat(true);
  INSERT INTO trujillo.sos_dispatch_events(case_id,operator_id,reason) VALUES(p_id,actor,'assignment_accepted');
  IF EXISTS(SELECT 1 FROM trujillo.sos_contact_requests WHERE case_id=p_id AND expires_at>now()) THEN
   PERFORM trujillo.sos_open_audio(p_id,actor);
   DELETE FROM trujillo.sos_contact_requests WHERE case_id=p_id;
  END IF;
  RETURN trujillo.sos_case_read(p_id);
 END IF;
 IF d.state='searching' THEN RAISE EXCEPTION 'Buscando un operador disponible'; END IF;
 PERFORM trujillo.operator_heartbeat(true);
 RETURN trujillo.claim_sos_v33(p_id);
END; $$;

CREATE FUNCTION trujillo.operator_handoff(p_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid;
BEGIN
 actor:=trujillo.current_actor(true);
 PERFORM pg_advisory_xact_lock(360017);
 IF NOT EXISTS(SELECT 1 FROM trujillo.sos_cases WHERE id=p_id AND operator_id=actor AND decision='confirmed' AND attention IN ('en_route','on_scene')) THEN
  RAISE EXCEPTION 'Caso no asignado' USING ERRCODE='42501'; END IF;
 UPDATE trujillo.sos_dispatch SET state='searching' WHERE case_id=p_id;
 PERFORM trujillo.sos_dispatch_tick();
 RETURN jsonb_build_object('transferring',true);
END; $$;

ALTER FUNCTION trujillo.sos_case_update(uuid,uuid,integer,jsonb) RENAME TO sos_case_update_v33;
CREATE FUNCTION trujillo.sos_case_update(p_id uuid,p_request uuid,p_version integer,p_data jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb;
BEGIN
 PERFORM pg_advisory_xact_lock(360017);
 IF EXISTS(SELECT 1 FROM trujillo.sos_cases WHERE id=p_id AND operator_id IS NOT NULL AND operator_id<>trujillo.current_actor(true))
 OR EXISTS(SELECT 1 FROM trujillo.help_requests WHERE id=p_id AND user_id=trujillo.current_actor(true)) THEN
  RAISE EXCEPTION 'Caso no asignado' USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM trujillo.sos_dispatch WHERE case_id=p_id AND state<>'assigned') THEN
  RAISE EXCEPTION 'La transferencia debe aceptarse primero' USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM trujillo.sos_case_events WHERE case_id=p_id AND request_id=p_request) THEN
  RETURN trujillo.sos_case_update_v33(p_id,p_request,p_version,p_data);
 END IF;
 IF EXISTS(SELECT 1 FROM trujillo.help_requests WHERE id=p_id AND stage IN ('Cerrada','Descartada')) THEN
  RAISE EXCEPTION 'Caso cerrado'; END IF;
 -- Preserve idempotent confirmations; claiming an already-owned case is harmless.
 IF p_data->>'action'='confirm' THEN PERFORM trujillo.claim_sos(p_id); END IF;
 result:=trujillo.sos_case_update_v33(p_id,p_request,p_version,p_data);
 IF result->>'decision'='confirmed' AND result->>'attention'<>'resolved' THEN
  INSERT INTO trujillo.sos_dispatch(case_id,state) VALUES(p_id,'assigned') ON CONFLICT(case_id) DO NOTHING;
  PERFORM trujillo.operator_heartbeat(true);
 END IF;
 RETURN trujillo.sos_case_read(p_id);
END; $$;

ALTER FUNCTION trujillo.citizen_call_operator(uuid) RENAME TO citizen_call_operator_v33;
CREATE FUNCTION trujillo.citizen_call_operator(p_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; h trujillo.help_requests; c trujillo.sos_cases; s trujillo.call_sessions; assigned_ready boolean;
BEGIN
 actor:=trujillo.current_actor(false);
 PERFORM pg_advisory_xact_lock(360017);
 SELECT * INTO h FROM trujillo.help_requests WHERE id=p_id AND user_id=actor AND source='sos' AND stage NOT IN ('Cerrada','Descartada');
 IF h.id IS NULL THEN RAISE EXCEPTION 'Caso no disponible' USING ERRCODE='42501'; END IF;
 SELECT * INTO c FROM trujillo.sos_cases WHERE id=p_id;
 SELECT * INTO s FROM trujillo.call_sessions WHERE id=p_id;
 assigned_ready:=c.decision='confirmed' AND EXISTS(SELECT 1 FROM trujillo.sos_dispatch WHERE case_id=p_id AND state='assigned');
 IF s.state IN ('waiting','accepted') AND s.expires_at>now() AND (c.decision IS DISTINCT FROM 'confirmed' OR assigned_ready) THEN
  IF s.direction='operator' AND s.state='waiting' THEN RETURN trujillo.call_action_v33(p_id,'answer'); END IF;
  RETURN trujillo.call_action_v33(p_id,'status');
 END IF;
 IF EXISTS(SELECT 1 FROM trujillo.sos_contact_requests WHERE case_id=p_id AND expires_at>now()) THEN
  RETURN jsonb_build_object('id',p_id,'state','waiting_assignment','can_join',false); END IF;
 IF EXISTS(SELECT 1 FROM trujillo.call_sessions WHERE id<>p_id AND citizen_id=actor AND state IN ('waiting','accepted') AND expires_at>now()) THEN
  RAISE EXCEPTION 'Tienes otra llamada activa'; END IF;
 IF NOT trujillo.sos_rate_allow(actor,'call') THEN RETURN jsonb_build_object('error_code','SOS_RATE_LIMIT','retry_after',60); END IF;
 IF c.decision IS DISTINCT FROM 'confirmed' THEN
  PERFORM trujillo.expire_sos_claims();
  SELECT operator_id INTO c.operator_id FROM trujillo.sos_cases WHERE id=p_id;
  PERFORM trujillo.sos_open_audio(p_id,c.operator_id);
  RETURN trujillo.call_action_v33(p_id,'status');
 END IF;
 IF NOT EXISTS(SELECT 1 FROM trujillo.operator_availability a JOIN trujillo.users u ON u.id=a.user_id
  WHERE a.user_id=c.operator_id AND a.online AND a.last_seen>now()-interval '120 seconds' AND u.status='active')
  OR EXISTS(SELECT 1 FROM trujillo.call_sessions WHERE id<>p_id AND state IN ('waiting','accepted') AND expires_at>now()
   AND (operator_id=c.operator_id OR citizen_id=c.operator_id)) THEN
  UPDATE trujillo.sos_dispatch SET state='searching' WHERE case_id=p_id;
 END IF;
 INSERT INTO trujillo.sos_contact_requests VALUES(p_id,now()+interval '90 seconds') ON CONFLICT(case_id) DO UPDATE SET expires_at=EXCLUDED.expires_at;
 PERFORM trujillo.sos_dispatch_tick();
 SELECT * INTO c FROM trujillo.sos_cases WHERE id=p_id;
 IF EXISTS(SELECT 1 FROM trujillo.sos_dispatch WHERE case_id=p_id AND state='assigned') THEN
  PERFORM trujillo.sos_open_audio(p_id,c.operator_id);
  DELETE FROM trujillo.sos_contact_requests WHERE case_id=p_id;
  RETURN trujillo.call_action_v33(p_id,'status');
 END IF;
 RETURN jsonb_build_object('id',p_id,'state','waiting_assignment','can_join',false);
END; $$;

ALTER FUNCTION trujillo.call_action(uuid,text) RENAME TO call_action_v33;
CREATE FUNCTION trujillo.call_action(p_id uuid,p_action text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; c trujillo.sos_cases; h trujillo.help_requests; s trujillo.call_sessions;
BEGIN
 actor:=trujillo.current_actor(false);
 PERFORM pg_advisory_xact_lock(360017);
 SELECT * INTO h FROM trujillo.help_requests WHERE id=p_id;
 SELECT * INTO c FROM trujillo.sos_cases WHERE id=p_id;
 SELECT * INTO s FROM trujillo.call_sessions WHERE id=p_id;
 IF c.decision='confirmed' AND h.user_id<>actor AND c.operator_id IS DISTINCT FROM actor THEN
  RAISE EXCEPTION 'El caso fue reasignado' USING ERRCODE='42501'; END IF;
 IF p_action='end' AND actor=h.user_id THEN
  DELETE FROM trujillo.sos_contact_requests WHERE case_id=p_id;
  IF EXISTS(SELECT 1 FROM trujillo.sos_dispatch WHERE case_id=p_id AND state<>'assigned') THEN
   RETURN jsonb_build_object('id',p_id,'state','ended','can_join',false,
    'room',coalesce('sos-'||p_id::text||'-'||s.generation::text,'sos-noaudio-'||p_id::text));
  END IF;
 END IF;
 IF p_action='status' AND actor=h.user_id AND c.decision='confirmed'
  AND EXISTS(SELECT 1 FROM trujillo.sos_dispatch WHERE case_id=p_id AND state<>'assigned') THEN
  IF EXISTS(SELECT 1 FROM trujillo.sos_contact_requests WHERE case_id=p_id AND expires_at>now()) THEN
   RETURN jsonb_build_object('id',p_id,'state','waiting_assignment','can_join',false); END IF;
  RETURN jsonb_build_object('id',p_id,'state','unanswered','can_join',false);
 END IF;
 IF p_action='start' THEN RETURN trujillo.citizen_call_operator(p_id); END IF;
 IF p_action IN ('accept','token','callback') AND c.decision='confirmed'
  AND EXISTS(SELECT 1 FROM trujillo.sos_dispatch WHERE case_id=p_id AND state<>'assigned') THEN
  RAISE EXCEPTION 'Debes aceptar la transferencia' USING ERRCODE='42501'; END IF;
 IF p_action='callback' AND NOT (s.state IN ('waiting','accepted') AND s.expires_at>now()) THEN
  IF NOT trujillo.sos_rate_allow(actor,'call') THEN RETURN jsonb_build_object('error_code','SOS_RATE_LIMIT','retry_after',60); END IF;
 END IF;
 RETURN trujillo.call_action_v33(p_id,p_action);
END; $$;

ALTER FUNCTION trujillo.sos_navigation_target(uuid) RENAME TO sos_navigation_target_v33;
CREATE FUNCTION trujillo.sos_navigation_target(p_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM trujillo.current_actor(true);
 IF EXISTS(SELECT 1 FROM trujillo.sos_dispatch WHERE case_id=p_id AND state<>'assigned') THEN
  RAISE EXCEPTION 'Asignación pendiente' USING ERRCODE='42501'; END IF;
 RETURN trujillo.sos_navigation_target_v33(p_id);
END; $$;

CREATE FUNCTION trujillo.sos_dispatch_fields(p_id uuid,p_operator boolean) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; c trujillo.sos_cases; d trujillo.sos_dispatch;
BEGIN
 actor:=trujillo.current_actor(p_operator);
 IF NOT p_operator AND NOT EXISTS(SELECT 1 FROM trujillo.help_requests WHERE id=p_id AND user_id=actor) THEN
  RAISE EXCEPTION 'Caso no disponible' USING ERRCODE='42501'; END IF;
 SELECT * INTO c FROM trujillo.sos_cases WHERE id=p_id;
 SELECT * INTO d FROM trujillo.sos_dispatch WHERE case_id=p_id;
 RETURN jsonb_build_object('assignment_state',coalesce(d.state,CASE WHEN c.operator_id IS NULL THEN 'searching' ELSE 'assigned' END),
  'assignment_offer',p_operator AND d.state='offered' AND c.operator_id=actor AND d.offer_expires_at>now() AND c.decision='confirmed' AND c.attention<>'resolved',
  'offer_expires_at',d.offer_expires_at,
  'operator_name',CASE WHEN d.state='assigned' THEN (SELECT display_name FROM trujillo.users WHERE id=c.operator_id) ELSE NULL END,
  'escalation_level',coalesce((SELECT level FROM trujillo.sos_escalation WHERE case_id=p_id),0));
END; $$;

ALTER FUNCTION trujillo.sos_case_read(uuid) RENAME TO sos_case_read_v33;
CREATE FUNCTION trujillo.sos_case_read(p_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb; fields jsonb;
BEGIN
 -- Read the base case first: an unaccepted offer must not request a route target.
 result:=trujillo.sos_case_read_v31(p_id);
 fields:=trujillo.sos_dispatch_fields(p_id,true);
 IF result->>'decision'='confirmed' AND fields->>'assignment_state'<>'assigned' THEN
  result:=result||jsonb_build_object('can_track',false,'can_edit',false,'attention','none');
 ELSIF result->>'decision'='confirmed' AND result->>'attention'<>'resolved' AND (result->>'can_track')::boolean THEN
  result:=result||jsonb_build_object('live_position',trujillo.sos_navigation_target(p_id));
 END IF;
 RETURN result||fields||jsonb_build_object('alert_in_range',trujillo.operator_in_sos_zone(trujillo.current_actor(true),p_id),
 'transfers',coalesce((SELECT jsonb_agg(to_jsonb(t)-'id'-'case_id')
  FROM (SELECT * FROM trujillo.sos_dispatch_events WHERE case_id=p_id ORDER BY id DESC LIMIT 50) t),'[]'::jsonb));
END; $$;

ALTER FUNCTION trujillo.operator_sos_map_data() RENAME TO operator_sos_map_data_v33;
CREATE FUNCTION trujillo.operator_sos_map_data() RETURNS SETOF jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r jsonb; fields jsonb;
BEGIN
 PERFORM trujillo.current_actor(true);
 FOR r IN SELECT * FROM trujillo.operator_sos_map_data_v33() LOOP
  fields:=trujillo.sos_dispatch_fields((r->>'id')::uuid,true);
  IF r->>'decision'='confirmed' AND fields->>'assignment_state'<>'assigned' THEN
   r:=r||jsonb_build_object('can_track',false,'attention','none');
  END IF;
  RETURN NEXT r||fields;
 END LOOP;
END; $$;

ALTER FUNCTION trujillo.citizen_sos_cases(uuid) RENAME TO citizen_sos_cases_v33;
CREATE FUNCTION trujillo.citizen_sos_cases(p_id uuid DEFAULT NULL) RETURNS SETOF jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r jsonb; fields jsonb;
BEGIN
 FOR r IN SELECT * FROM trujillo.citizen_sos_cases_v33(p_id) LOOP
  fields:=trujillo.sos_dispatch_fields((r->>'id')::uuid,false);
  IF r->>'attention'<>'resolved' AND fields->>'assignment_state'<>'assigned' THEN
   r:=r||jsonb_build_object('attention','none');
  END IF;
  RETURN NEXT r||fields;
 END LOOP;
END; $$;

ALTER FUNCTION trujillo.push_claim() RENAME TO push_claim_v33;
CREATE FUNCTION trujillo.push_claim() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb; job trujillo.push_outbox;
BEGIN
 result:=trujillo.push_claim_v33();
 IF result IS NULL OR result->>'skipped'='true' THEN RETURN result; END IF;
 SELECT * INTO job FROM trujillo.push_outbox WHERE id=(result->>'job_id')::uuid;
 IF job.event_key LIKE 'assignment:%' THEN
  IF NOT EXISTS(SELECT 1 FROM trujillo.sos_dispatch d JOIN trujillo.sos_cases c ON c.id=d.case_id
   WHERE c.id=job.target_id AND c.operator_id=job.user_id AND c.decision='confirmed' AND c.attention<>'resolved'
   AND d.state='offered' AND d.offer_expires_at>now() AND job.event_key='assignment:'||c.id::text||':'||d.generation::text) THEN
   UPDATE trujillo.push_outbox SET done=true WHERE id=job.id; RETURN jsonb_build_object('skipped',true); END IF;
  RETURN result||jsonb_build_object('assignment_offer',true,'quiet',false,'title','SOS: se solicita tu atención',
   'body','Eres el operador disponible más cercano. Abre la app y acepta la transferencia.');
 END IF;
 IF job.event_key LIKE 'escalation:%' AND
 (EXISTS(SELECT 1 FROM trujillo.sos_cases WHERE id=job.target_id AND
   (decision<>'pending' OR (operator_id IS NOT NULL AND claim_expires_at>now())))
  OR EXISTS(SELECT 1 FROM trujillo.help_requests WHERE id=job.target_id AND stage IN ('Cerrada','Descartada'))) THEN
  UPDATE trujillo.push_outbox SET done=true WHERE id=job.id; RETURN jsonb_build_object('skipped',true);
 END IF;
 RETURN result;
END; $$;

CREATE FUNCTION trujillo.sos_cleanup_claim() RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE target text;
BEGIN
 SELECT room INTO target FROM trujillo.sos_room_cleanup WHERE next_at<=now() ORDER BY next_at FOR UPDATE SKIP LOCKED LIMIT 1;
 IF target IS NOT NULL THEN UPDATE trujillo.sos_room_cleanup SET next_at=now()+interval '30 seconds',attempts=attempts+1 WHERE room=target; END IF;
 RETURN target;
END; $$;
CREATE FUNCTION trujillo.sos_cleanup_finish(p_room text) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$ DELETE FROM trujillo.sos_room_cleanup WHERE room=p_room $$;

-- None of the superseded wrappers or internal helpers are callable by API clients.
REVOKE ALL ON FUNCTION trujillo.operator_position_v33(double precision,double precision,double precision,timestamptz),
 trujillo.submit_sos_v33(uuid,double precision,double precision),trujillo.claim_sos_v33(uuid),
 trujillo.sos_case_update_v33(uuid,uuid,integer,jsonb),trujillo.citizen_call_operator_v33(uuid),
 trujillo.call_action_v33(uuid,text),trujillo.sos_case_read_v33(uuid),trujillo.operator_sos_map_data_v33(),
 trujillo.citizen_sos_cases_v33(uuid),trujillo.push_claim_v33(),trujillo.sos_end_audio(uuid),
 trujillo.sos_navigation_target_v33(uuid),
 trujillo.sos_open_audio(uuid,uuid),trujillo.sos_rate_allow(uuid,text),trujillo.sos_dispatch_fields(uuid,boolean)
 FROM PUBLIC,anon,authenticated,trujillo_api;
REVOKE ALL ON FUNCTION trujillo.operator_heartbeat(boolean),trujillo.operator_begin_duty(),
 trujillo.operator_position(double precision,double precision,double precision,timestamptz),
 trujillo.submit_sos(uuid,double precision,double precision),trujillo.claim_sos(uuid),
 trujillo.sos_case_update(uuid,uuid,integer,jsonb),trujillo.citizen_call_operator(uuid),trujillo.call_action(uuid,text),
 trujillo.sos_case_read(uuid),trujillo.operator_sos_map_data(),trujillo.citizen_sos_cases(uuid),trujillo.push_claim(),
 trujillo.sos_navigation_target(uuid),
 trujillo.sos_dispatch_tick(),trujillo.operator_handoff(uuid),trujillo.sos_cleanup_claim(),trujillo.sos_cleanup_finish(text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION trujillo.operator_heartbeat(boolean),trujillo.operator_begin_duty(),
 trujillo.operator_position(double precision,double precision,double precision,timestamptz),
 trujillo.submit_sos(uuid,double precision,double precision),trujillo.claim_sos(uuid),
 trujillo.sos_case_update(uuid,uuid,integer,jsonb),trujillo.citizen_call_operator(uuid),trujillo.call_action(uuid,text),
 trujillo.sos_case_read(uuid),trujillo.operator_sos_map_data(),trujillo.citizen_sos_cases(uuid),trujillo.push_claim(),
 trujillo.sos_navigation_target(uuid),
 trujillo.sos_dispatch_tick(),trujillo.operator_handoff(uuid),trujillo.sos_cleanup_claim(),trujillo.sos_cleanup_finish(text)
 TO trujillo_api;
