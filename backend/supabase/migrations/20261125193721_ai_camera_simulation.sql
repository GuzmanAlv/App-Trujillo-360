-- Explicitly provisioned simulation camera; no public incidents or push outbox.
CREATE TABLE trujillo.sim_camera_permissions(
 email text PRIMARY KEY CHECK(email=lower(trim(email))),
 camera_id text UNIQUE NOT NULL REFERENCES trujillo.ai_cameras(id),
 enabled boolean NOT NULL DEFAULT true,
 threshold double precision NOT NULL DEFAULT .85 CHECK(threshold BETWEEN .5 AND 1));
CREATE TABLE trujillo.sim_sessions(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 owner_id uuid NOT NULL REFERENCES trujillo.users(id),
 camera_id text NOT NULL REFERENCES trujillo.ai_cameras(id),
 latitude double precision NOT NULL CHECK(latitude BETWEEN -90 AND 90),
 longitude double precision NOT NULL CHECK(longitude BETWEEN -180 AND 180),
 token_hash text NOT NULL CHECK(token_hash ~ '^[0-9a-f]{64}$'),
 expires_at timestamptz NOT NULL DEFAULT now()+interval '30 minutes',
 stopped boolean NOT NULL DEFAULT false,
 consecutive integer NOT NULL DEFAULT 0,
 last_observed_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX sim_sessions_owner ON trujillo.sim_sessions(owner_id,created_at DESC);
CREATE TABLE trujillo.sim_cases(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 session_id uuid NOT NULL REFERENCES trujillo.sim_sessions(id),
 camera_id text NOT NULL REFERENCES trujillo.ai_cameras(id),
 latitude double precision NOT NULL, longitude double precision NOT NULL,
 confidence double precision NOT NULL CHECK(confidence BETWEEN 0 AND 1),
 model_version text NOT NULL,
 stage text NOT NULL DEFAULT 'Recibida' CHECK(stage IN ('Recibida','En revisión','Acción registrada','Cerrada','Descartada')),
 received_at timestamptz NOT NULL DEFAULT clock_timestamp());
CREATE INDEX sim_cases_queue ON trujillo.sim_cases(received_at DESC,id);
CREATE INDEX sim_cases_camera_cooldown ON trujillo.sim_cases(camera_id,received_at DESC);
CREATE INDEX sim_cases_session ON trujillo.sim_cases(session_id);
CREATE TABLE trujillo.sim_case_events(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 case_id uuid NOT NULL REFERENCES trujillo.sim_cases(id),
 actor_id uuid NOT NULL REFERENCES trujillo.users(id), stage text NOT NULL,
 reason text NOT NULL CHECK(length(trim(reason)) BETWEEN 5 AND 500),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp());
CREATE INDEX sim_case_events_case ON trujillo.sim_case_events(case_id,id);
CREATE TABLE trujillo.sim_received_windows(
 session_id uuid NOT NULL REFERENCES trujillo.sim_sessions(id), request_id uuid NOT NULL,
 confidence double precision NOT NULL, model_version text NOT NULL, result jsonb NOT NULL,
 PRIMARY KEY(session_id,request_id));
ALTER TABLE trujillo.sim_camera_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE trujillo.sim_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE trujillo.sim_cases ENABLE ROW LEVEL SECURITY;
ALTER TABLE trujillo.sim_case_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE trujillo.sim_received_windows ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON trujillo.sim_camera_permissions,trujillo.sim_sessions,trujillo.sim_cases,trujillo.sim_case_events,trujillo.sim_received_windows FROM PUBLIC,anon,authenticated,trujillo_api;

CREATE FUNCTION trujillo.simulation_config() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; result jsonb;
BEGIN
 actor:=trujillo.current_actor(true);
 SELECT jsonb_build_object('enabled',true,'cameraId',p.camera_id,'threshold',p.threshold)
 INTO result FROM trujillo.sim_camera_permissions p JOIN trujillo.users u ON u.auth_email=p.email
 JOIN trujillo.ai_cameras c ON c.id=p.camera_id AND c.active
 WHERE u.id=actor AND p.enabled;
 RETURN COALESCE(result,jsonb_build_object('enabled',false,'cameraId','','threshold',.85));
END; $$;
CREATE FUNCTION trujillo.create_sim_session(p_camera text,p_lat double precision,p_lng double precision,p_hash text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; config jsonb; result trujillo.sim_sessions;
BEGIN
 actor:=trujillo.current_actor(true); config:=trujillo.simulation_config();
 IF config->>'enabled'<>'true' OR config->>'cameraId' IS DISTINCT FROM p_camera THEN
  RAISE EXCEPTION 'Camera not enabled' USING ERRCODE='42501'; END IF;
 IF p_lat IS NULL OR NOT(p_lat BETWEEN -90 AND 90) OR p_lng IS NULL OR NOT(p_lng BETWEEN -180 AND 180)
 OR p_hash IS NULL OR p_hash !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'Invalid session' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(actor::text,360025));
 UPDATE trujillo.sim_sessions SET stopped=true WHERE owner_id=actor AND NOT stopped;
 INSERT INTO trujillo.sim_sessions(owner_id,camera_id,latitude,longitude,token_hash)
 VALUES(actor,p_camera,p_lat,p_lng,p_hash) RETURNING * INTO result;
 RETURN jsonb_build_object('id',result.id,'expiresAt',result.expires_at,'cameraId',p_camera);
END; $$;
CREATE FUNCTION trujillo.stop_sim_session(p_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid;
BEGIN
 actor:=trujillo.current_actor(true);
 UPDATE trujillo.sim_sessions SET stopped=true WHERE id=p_id AND owner_id=actor;
 IF NOT FOUND THEN RAISE EXCEPTION 'Session unavailable' USING ERRCODE='P0002'; END IF;
 RETURN jsonb_build_object('status','stopped');
END; $$;
CREATE FUNCTION trujillo.sim_case_json(p_case trujillo.sim_cases) RETURNS jsonb
LANGUAGE sql STABLE SET search_path='' AS $$
 SELECT jsonb_build_object('id',p_case.id,'simulation',true,'cameraId',p_case.camera_id,
 'latitude',p_case.latitude,'longitude',p_case.longitude,'confidence',p_case.confidence,
 'modelVersion',p_case.model_version,'stage',p_case.stage,'receivedAt',p_case.received_at,
 'events',COALESCE((SELECT jsonb_agg(jsonb_build_object('stage',e.stage,'reason',e.reason,'at',e.created_at,'actor',u.display_name) ORDER BY e.id)
 FROM trujillo.sim_case_events e JOIN trujillo.users u ON u.id=e.actor_id WHERE e.case_id=p_case.id),'[]'::jsonb));
$$;
CREATE FUNCTION trujillo.receive_sim_event(p_session uuid,p_hash text,p_request uuid,p_confidence double precision,p_model text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE session trujillo.sim_sessions; owner trujillo.users; threshold double precision;
 old trujillo.sim_received_windows; new_case trujillo.sim_cases; result jsonb; hits integer;
BEGIN
 SELECT * INTO session FROM trujillo.sim_sessions WHERE id=p_session FOR UPDATE;
 IF NOT FOUND OR p_hash IS NULL OR session.token_hash IS DISTINCT FROM p_hash THEN
  RAISE EXCEPTION 'Invalid worker credential' USING ERRCODE='28000'; END IF;
 SELECT * INTO owner FROM trujillo.users WHERE id=session.owner_id AND status='active' AND role IN ('operator','admin') FOR SHARE;
 SELECT p.threshold INTO threshold FROM trujillo.sim_camera_permissions p JOIN trujillo.ai_cameras c ON c.id=p.camera_id AND c.active
 WHERE p.email=owner.auth_email AND p.camera_id=session.camera_id AND p.enabled FOR SHARE OF p,c;
 IF owner.id IS NULL OR threshold IS NULL THEN RAISE EXCEPTION 'Permission revoked' USING ERRCODE='42501'; END IF;
 IF session.stopped OR session.expires_at<=clock_timestamp() THEN RAISE EXCEPTION 'Session expired' USING ERRCODE='P0001'; END IF;
 IF p_request IS NULL OR p_confidence IS NULL OR NOT(p_confidence BETWEEN 0 AND 1) OR p_model IS NULL OR length(trim(p_model)) NOT BETWEEN 1 AND 200 THEN
  RAISE EXCEPTION 'Invalid observation' USING ERRCODE='22023'; END IF;
 SELECT * INTO old FROM trujillo.sim_received_windows WHERE session_id=p_session AND request_id=p_request;
 IF FOUND THEN
  IF (old.confidence,old.model_version) IS DISTINCT FROM (p_confidence,p_model) THEN RAISE EXCEPTION 'Immutable observation' USING ERRCODE='P0001'; END IF;
  RETURN old.result;
 END IF;
 IF (SELECT count(*) FROM trujillo.sim_received_windows WHERE session_id=p_session)>=1024 THEN
  RAISE EXCEPTION 'Session observation limit' USING ERRCODE='P0001'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(session.camera_id,360026));
 IF session.expires_at<=clock_timestamp() THEN RAISE EXCEPTION 'Session expired' USING ERRCODE='P0001'; END IF;
 hits:=CASE WHEN p_confidence>=threshold THEN
 CASE WHEN session.last_observed_at>clock_timestamp()-interval '10 seconds' THEN session.consecutive+1 ELSE 1 END ELSE 0 END;
 IF hits=0 THEN result:=jsonb_build_object('status','below_threshold','case',null);
 ELSIF EXISTS(SELECT 1 FROM trujillo.sim_cases WHERE camera_id=session.camera_id AND received_at>clock_timestamp()-interval '60 seconds') THEN
  result:=jsonb_build_object('status','cooldown','case',null); hits:=0;
 ELSIF hits<2 THEN result:=jsonb_build_object('status','warming_up','case',null);
 ELSE
  INSERT INTO trujillo.sim_cases(session_id,camera_id,latitude,longitude,confidence,model_version)
  VALUES(p_session,session.camera_id,session.latitude,session.longitude,p_confidence,p_model) RETURNING * INTO new_case;
  INSERT INTO trujillo.sim_case_events(case_id,actor_id,stage,reason)
  VALUES(new_case.id,session.owner_id,'Recibida','Simulación IA: posible forcejeo detectado. Requiere revisión del operador.');
  result:=jsonb_build_object('status','created','case',trujillo.sim_case_json(new_case)); hits:=0;
 END IF;
 UPDATE trujillo.sim_sessions SET consecutive=hits,last_observed_at=clock_timestamp() WHERE id=p_session;
 INSERT INTO trujillo.sim_received_windows VALUES(p_session,p_request,p_confidence,p_model,result);
 RETURN result;
END; $$;
CREATE FUNCTION trujillo.sim_cases() RETURNS SETOF jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM trujillo.current_actor(true);
 RETURN QUERY SELECT trujillo.sim_case_json(c) FROM trujillo.sim_cases c
 ORDER BY (c.stage IN ('Cerrada','Descartada')),c.received_at DESC,c.id LIMIT 200;
END; $$;
CREATE FUNCTION trujillo.review_sim_case(p_id uuid,p_stage text,p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; item trujillo.sim_cases; latest trujillo.sim_case_events;
BEGIN
 actor:=trujillo.current_actor(true);
 SELECT * INTO item FROM trujillo.sim_cases WHERE id=p_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Case unavailable' USING ERRCODE='P0002'; END IF;
 IF p_reason IS NULL OR length(trim(p_reason)) NOT BETWEEN 5 AND 500 OR p_stage IS NULL THEN
  RAISE EXCEPTION 'Invalid reason' USING ERRCODE='22023'; END IF;
 SELECT * INTO latest FROM trujillo.sim_case_events WHERE case_id=p_id ORDER BY id DESC LIMIT 1;
 IF (latest.stage,latest.actor_id,latest.reason) IS NOT DISTINCT FROM (p_stage,actor,trim(p_reason)) THEN RETURN trujillo.sim_case_json(item); END IF;
 IF NOT ((item.stage='Recibida' AND p_stage IN ('En revisión','Descartada'))
 OR (item.stage IN ('En revisión','Acción registrada') AND p_stage IN ('Acción registrada','Cerrada','Descartada'))) THEN
  RAISE EXCEPTION 'Invalid transition' USING ERRCODE='22023'; END IF;
 UPDATE trujillo.sim_cases SET stage=p_stage WHERE id=p_id RETURNING * INTO item;
 INSERT INTO trujillo.sim_case_events(case_id,actor_id,stage,reason) VALUES(p_id,actor,p_stage,trim(p_reason));
 RETURN trujillo.sim_case_json(item);
END; $$;
REVOKE ALL ON FUNCTION trujillo.simulation_config(),trujillo.create_sim_session(text,double precision,double precision,text),trujillo.stop_sim_session(uuid),trujillo.sim_case_json(trujillo.sim_cases),trujillo.receive_sim_event(uuid,text,uuid,double precision,text),trujillo.sim_cases(),trujillo.review_sim_case(uuid,text,text) FROM PUBLIC,anon,authenticated,trujillo_api;
GRANT EXECUTE ON FUNCTION trujillo.simulation_config(),trujillo.create_sim_session(text,double precision,double precision,text),trujillo.stop_sim_session(uuid),trujillo.receive_sim_event(uuid,text,uuid,double precision,text),trujillo.sim_cases(),trujillo.review_sim_case(uuid,text,text) TO trujillo_api;
-- Camera permission is explicitly provisioned separately for the chosen account.
INSERT INTO trujillo.ai_migrations VALUES(2);
