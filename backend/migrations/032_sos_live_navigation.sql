-- Live positions are private, separate from the incident's recorded location.
CREATE TABLE trujillo.sos_live_positions (
 case_id uuid PRIMARY KEY REFERENCES trujillo.help_requests(id) ON DELETE CASCADE,
 latitude double precision NOT NULL, longitude double precision NOT NULL,
 accuracy double precision NOT NULL, observed_at timestamptz NOT NULL
);
ALTER TABLE trujillo.sos_live_positions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON trujillo.sos_live_positions FROM PUBLIC,anon,authenticated,trujillo_api;

CREATE FUNCTION trujillo.sos_live_position(p_id uuid,p_lat double precision,p_lng double precision,
 p_accuracy double precision,p_observed timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; active boolean;
BEGIN
 actor:=trujillo.current_actor(false);
 SELECT c.decision='confirmed' AND c.attention IN ('en_route','on_scene') AND h.stage NOT IN ('Cerrada','Descartada')
 INTO active FROM trujillo.help_requests h JOIN trujillo.sos_cases c ON c.id=h.id WHERE h.id=p_id AND h.user_id=actor;
 IF active IS DISTINCT FROM true THEN RAISE EXCEPTION 'Caso no disponible' USING ERRCODE='42501'; END IF;
 IF p_lat IS NULL OR p_lng IS NULL OR p_accuracy IS NULL OR p_observed IS NULL OR
 NOT (p_lat BETWEEN -90 AND 90 AND p_lng BETWEEN -180 AND 180 AND p_accuracy BETWEEN 0 AND 50)
 OR p_observed<clock_timestamp()-interval '30 seconds' OR p_observed>clock_timestamp()+interval '5 seconds' THEN
 RAISE EXCEPTION 'GPS impreciso o antiguo' USING ERRCODE='22023'; END IF;
 INSERT INTO trujillo.sos_live_positions VALUES(p_id,p_lat,p_lng,p_accuracy,p_observed)
 ON CONFLICT(case_id) DO UPDATE SET latitude=p_lat,longitude=p_lng,accuracy=p_accuracy,observed_at=p_observed
 WHERE sos_live_positions.observed_at<EXCLUDED.observed_at;
 RETURN jsonb_build_object('status','saved');
END; $$;

CREATE FUNCTION trujillo.sos_navigation_target(p_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; c trujillo.sos_cases; pos trujillo.sos_live_positions;
BEGIN
 actor:=trujillo.current_actor(true);
 SELECT * INTO c FROM trujillo.sos_cases WHERE id=p_id;
 IF c.operator_id IS DISTINCT FROM actor THEN RAISE EXCEPTION 'Caso no asignado' USING ERRCODE='42501'; END IF;
 IF c.decision<>'confirmed' OR c.attention NOT IN ('en_route','on_scene') THEN RAISE EXCEPTION 'Caso cerrado'; END IF;
 SELECT * INTO pos FROM trujillo.sos_live_positions WHERE case_id=p_id;
 RETURN jsonb_build_object('latitude',coalesce(pos.latitude,c.latitude),'longitude',coalesce(pos.longitude,c.longitude),
 'live',coalesce(pos.observed_at>clock_timestamp()-interval '60 seconds',false),
 'stale',coalesce(pos.observed_at<=clock_timestamp()-interval '60 seconds',false),'observed_at',pos.observed_at);
END; $$;

ALTER FUNCTION trujillo.sos_case_read(uuid) RENAME TO sos_case_read_v31;
CREATE FUNCTION trujillo.sos_case_read(p_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb;
BEGIN
 result:=trujillo.sos_case_read_v31(p_id);
 IF (result->>'can_track')::boolean AND result->>'decision'='confirmed' AND result->>'attention'<>'resolved' THEN
  result:=result||jsonb_build_object('live_position',trujillo.sos_navigation_target(p_id));
 END IF;
 RETURN result;
END; $$;

-- Per-user lock also serializes concurrent retries with different request IDs.
ALTER FUNCTION trujillo.submit_sos(uuid,double precision,double precision) RENAME TO submit_sos_v31;
CREATE FUNCTION trujillo.submit_sos(p_request uuid,p_lat double precision,p_lng double precision) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; active trujillo.help_requests;
BEGIN
 actor:=trujillo.current_actor(false);
 PERFORM pg_advisory_xact_lock(360017);
 PERFORM pg_advisory_xact_lock(hashtextextended('active-sos:'||actor::text,0));
 IF EXISTS(SELECT 1 FROM trujillo.help_requests WHERE user_id=actor AND request_id=p_request) THEN
  RETURN trujillo.submit_sos_v31(p_request,p_lat,p_lng);
 END IF;
 SELECT h.* INTO active FROM trujillo.help_requests h JOIN trujillo.sos_cases c ON c.id=h.id
 WHERE h.user_id=actor AND c.decision='confirmed' AND c.attention IN ('en_route','on_scene')
 AND h.stage NOT IN ('Cerrada','Descartada') ORDER BY h.received_at DESC LIMIT 1;
 IF FOUND THEN RETURN (to_jsonb(active)-'user_id')||jsonb_build_object('existing_active',true); END IF;
 RETURN trujillo.submit_sos_v31(p_request,p_lat,p_lng);
END; $$;

-- Reopen audio on the same confirmed case, always to its assigned operator.
CREATE FUNCTION trujillo.citizen_call_operator(p_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; assigned uuid; s trujillo.call_sessions;
BEGIN
 actor:=trujillo.current_actor(false);
 PERFORM pg_advisory_xact_lock(360017);
 SELECT c.operator_id INTO assigned FROM trujillo.sos_cases c JOIN trujillo.help_requests h ON h.id=c.id
 JOIN trujillo.users u ON u.id=c.operator_id
 WHERE c.id=p_id AND h.user_id=actor AND c.decision='confirmed' AND c.attention IN ('en_route','on_scene')
 AND h.stage NOT IN ('Cerrada','Descartada') AND u.status='active';
 IF assigned IS NULL THEN RAISE EXCEPTION 'Caso no disponible' USING ERRCODE='42501'; END IF;
 SELECT * INTO s FROM trujillo.call_sessions WHERE id=p_id FOR UPDATE;
 IF s.state IN ('waiting','accepted') AND s.expires_at>now() THEN
  IF s.state='waiting' AND s.direction='operator' THEN RETURN trujillo.call_action(p_id,'answer'); END IF;
  RETURN trujillo.call_action(p_id,'status');
 END IF;
 IF EXISTS(SELECT 1 FROM trujillo.call_sessions WHERE id<>p_id AND state IN ('waiting','accepted') AND expires_at>now()
 AND (citizen_id IN (actor,assigned) OR operator_id IN (actor,assigned))) THEN RAISE EXCEPTION 'Participante ocupado'; END IF;
 INSERT INTO trujillo.call_sessions(id,citizen_id,operator_id) VALUES(p_id,actor,assigned)
 ON CONFLICT(id) DO UPDATE SET direction='citizen',generation=gen_random_uuid(),state='waiting',operator_id=assigned,
 created_at=now(),accepted_at=NULL,ended_at=NULL,expires_at=now()+interval '90 seconds';
 INSERT INTO trujillo.help_events(request_id,actor_id,stage,priority,reason)
 SELECT id,actor,stage,priority,'El ciudadano llama al operador asignado.' FROM trujillo.help_requests WHERE id=p_id;
 INSERT INTO trujillo.push_outbox(device_id,user_id,event_key,kind,target_id,expires_at)
 SELECT d.id,d.user_id,'redial:'||p_id::text||':'||s2.generation::text,'operator',p_id,now()+interval '90 seconds'
 FROM trujillo.push_devices d CROSS JOIN trujillo.call_sessions s2
 WHERE d.user_id=assigned AND d.operator_enabled AND s2.id=p_id
 ON CONFLICT(device_id,event_key) DO NOTHING;
 RETURN trujillo.call_action(p_id,'status');
END; $$;

CREATE FUNCTION trujillo.assigned_incoming_calls() RETURNS SETOF jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid;
BEGIN
 actor:=trujillo.current_actor(true);
 RETURN QUERY SELECT jsonb_build_object('id',s.id,'created_at',s.created_at,'expires_at',s.expires_at,'assigned',true)
 FROM trujillo.call_sessions s JOIN trujillo.sos_cases c ON c.id=s.id
 WHERE s.operator_id=actor AND c.operator_id=actor AND c.decision='confirmed' AND c.attention IN ('en_route','on_scene')
 AND s.direction='citizen' AND s.state='waiting' AND s.expires_at>now();
END; $$;

REVOKE ALL ON FUNCTION trujillo.sos_case_read_v31(uuid),trujillo.submit_sos_v31(uuid,double precision,double precision)
 FROM PUBLIC,anon,authenticated,trujillo_api;
REVOKE ALL ON FUNCTION trujillo.sos_live_position(uuid,double precision,double precision,double precision,timestamptz),
 trujillo.sos_navigation_target(uuid),trujillo.sos_case_read(uuid),trujillo.submit_sos(uuid,double precision,double precision),
 trujillo.citizen_call_operator(uuid),trujillo.assigned_incoming_calls() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION trujillo.sos_live_position(uuid,double precision,double precision,double precision,timestamptz),
 trujillo.sos_navigation_target(uuid),trujillo.sos_case_read(uuid),trujillo.submit_sos(uuid,double precision,double precision),
 trujillo.citizen_call_operator(uuid),trujillo.assigned_incoming_calls() TO trujillo_api;

-- A redial alerts only the assigned operator and expires with that generation.
ALTER FUNCTION trujillo.push_claim() RENAME TO push_claim_v31;
CREATE FUNCTION trujillo.push_claim() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb; job trujillo.push_outbox;
BEGIN
 result:=trujillo.push_claim_v31();
 IF result IS NULL OR result->>'skipped'='true' THEN RETURN result; END IF;
 SELECT * INTO job FROM trujillo.push_outbox WHERE id=(result->>'job_id')::uuid;
 IF job.event_key LIKE 'redial:%' THEN
  IF NOT EXISTS(SELECT 1 FROM trujillo.call_sessions s JOIN trujillo.sos_cases c ON c.id=s.id
   WHERE s.id=job.target_id AND s.operator_id=job.user_id AND c.operator_id=job.user_id
   AND s.direction='citizen' AND s.state='waiting' AND s.expires_at>now()
   AND c.decision='confirmed' AND c.attention IN ('en_route','on_scene')
   AND job.event_key='redial:'||s.id::text||':'||s.generation::text) THEN
   UPDATE trujillo.push_outbox SET done=true WHERE id=job.id;
   RETURN jsonb_build_object('skipped',true);
  END IF;
  RETURN result||jsonb_build_object('quiet',false,'assigned_call',true,
   'title','El ciudadano de tu SOS te llama','body','Abre Trujillo 360 para responder la llamada de tu caso.');
 END IF;
 RETURN result;
END; $$;
REVOKE ALL ON FUNCTION trujillo.push_claim_v31() FROM PUBLIC,anon,authenticated,trujillo_api;
REVOKE ALL ON FUNCTION trujillo.push_claim() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION trujillo.push_claim() TO trujillo_api;

CREATE OR REPLACE FUNCTION trujillo.sos_arrival_check(p_id uuid,p_lat double precision,p_lng double precision,
 p_accuracy double precision,p_observed timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; c trujillo.sos_cases; assigned uuid; sample trujillo.sos_arrival_samples;
 now_at timestamptz:=clock_timestamp(); inside boolean; target jsonb;
BEGIN
 actor:=trujillo.current_actor(true);
 PERFORM pg_advisory_xact_lock(360017);
 SELECT * INTO c FROM trujillo.sos_cases WHERE id=p_id FOR UPDATE;
 SELECT operator_id INTO assigned FROM trujillo.call_sessions WHERE id=p_id;
 IF c.id IS NULL OR coalesce(assigned,c.operator_id) IS DISTINCT FROM actor OR c.operator_id IS DISTINCT FROM actor THEN
  RAISE EXCEPTION 'Caso no asignado' USING ERRCODE='42501'; END IF;
 IF c.decision<>'confirmed' OR c.attention<>'en_route' THEN
  RETURN jsonb_build_object('attention',c.attention,'tracking',false); END IF;
 IF p_lat IS NULL OR p_lng IS NULL OR p_accuracy IS NULL OR p_observed IS NULL
 OR NOT (p_lat BETWEEN -90 AND 90 AND p_lng BETWEEN -180 AND 180 AND p_accuracy BETWEEN 0 AND 30)
 OR p_observed<now_at-interval '30 seconds' OR p_observed>now_at+interval '5 seconds' THEN
  DELETE FROM trujillo.sos_arrival_samples WHERE case_id=p_id;
  RETURN jsonb_build_object('attention',c.attention,'tracking',true,'reason','gps_quality'); END IF;
 target:=trujillo.sos_navigation_target(p_id);
 IF (target->>'stale')::boolean THEN
  DELETE FROM trujillo.sos_arrival_samples WHERE case_id=p_id;
  RETURN jsonb_build_object('attention',c.attention,'tracking',true,'reason','citizen_gps_stale');
 END IF;
 inside:=extensions.ST_DWithin(
  extensions.ST_SetSRID(extensions.ST_MakePoint(p_lng,p_lat),4326)::extensions.geography,
  extensions.ST_SetSRID(extensions.ST_MakePoint((target->>'longitude')::double precision,(target->>'latitude')::double precision),4326)::extensions.geography,50);
 IF NOT inside THEN
  DELETE FROM trujillo.sos_arrival_samples WHERE case_id=p_id;
  RETURN jsonb_build_object('attention',c.attention,'tracking',true,'reason','outside'); END IF;
 SELECT * INTO sample FROM trujillo.sos_arrival_samples WHERE case_id=p_id;
 IF sample.case_id IS NULL OR sample.actor_id<>actor OR sample.observed_at<now_at-interval '60 seconds' THEN
  INSERT INTO trujillo.sos_arrival_samples(case_id,actor_id,first_at,observed_at)
  VALUES(p_id,actor,now_at,p_observed) ON CONFLICT(case_id) DO UPDATE SET
  actor_id=actor,first_at=now_at,observed_at=p_observed,ready_at=NULL;
 ELSIF now_at-sample.first_at>=interval '10 seconds' AND p_observed-sample.observed_at>=interval '5 seconds' THEN
  UPDATE trujillo.sos_arrival_samples SET ready_at=now_at WHERE case_id=p_id;
  PERFORM trujillo.sos_case_update(p_id,gen_random_uuid(),c.version,jsonb_build_object(
   'action','on_scene','category',c.category,'latitude',c.latitude,'longitude',c.longitude,
   'place',c.place,'public_description',c.public_description,'internal_note',c.internal_note,'outcome',c.outcome,
   'arrival_position',jsonb_build_object('latitude',p_lat,'longitude',p_lng,'accuracy',p_accuracy)));
  DELETE FROM trujillo.sos_arrival_samples WHERE case_id=p_id;
  RETURN jsonb_build_object('attention','on_scene','tracking',false);
 END IF;
 RETURN jsonb_build_object('attention',c.attention,'tracking',true,'reason','checking');
END; $$;
REVOKE ALL ON FUNCTION trujillo.sos_arrival_check(uuid,double precision,double precision,double precision,timestamptz) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION trujillo.sos_arrival_check(uuid,double precision,double precision,double precision,timestamptz) TO trujillo_api;

