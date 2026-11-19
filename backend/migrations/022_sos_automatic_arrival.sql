-- Atomic dispatch and private GPS arrival debounce.
CREATE TABLE trujillo.sos_arrival_samples (
 case_id uuid PRIMARY KEY REFERENCES trujillo.sos_cases(id) ON DELETE CASCADE,
 actor_id uuid NOT NULL REFERENCES trujillo.users(id),
 first_at timestamptz NOT NULL, observed_at timestamptz NOT NULL, ready_at timestamptz
);
ALTER TABLE trujillo.sos_arrival_samples ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON trujillo.sos_arrival_samples FROM PUBLIC,anon,authenticated,trujillo_api;

CREATE OR REPLACE FUNCTION trujillo.sos_case_read(p_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor trujillo.users; h trujillo.help_requests; c trujillo.sos_cases; assigned uuid;
BEGIN
 SELECT * INTO actor FROM trujillo.users WHERE id=trujillo.current_actor(true);
 SELECT * INTO h FROM trujillo.help_requests WHERE id=p_id AND source='sos';
 IF h.id IS NULL THEN RAISE EXCEPTION 'SOS no disponible' USING ERRCODE='P0002'; END IF;
 SELECT * INTO c FROM trujillo.sos_cases WHERE id=p_id;
 SELECT operator_id INTO assigned FROM trujillo.call_sessions WHERE id=p_id;
 RETURN jsonb_build_object('id',h.id,'caller_latitude',h.latitude,'caller_longitude',h.longitude,
  'received_at',h.received_at,'version',coalesce(c.version,0),
  'support_requested',coalesce(c.support_requested,false),'call_direction',(SELECT direction FROM trujillo.call_sessions WHERE id=p_id),'call_state',(SELECT state FROM trujillo.call_sessions WHERE id=p_id),'decision',coalesce(c.decision,'pending'),'attention',coalesce(c.attention,'none'),
  'category',coalesce(c.category,h.category),'latitude',coalesce(c.latitude,h.latitude),
  'longitude',coalesce(c.longitude,h.longitude),'place',coalesce(c.place,''),
  'public_description',coalesce(c.public_description,''),'internal_note',coalesce(c.internal_note,''),
  'outcome',coalesce(c.outcome,''),'incident_id',c.incident_id,
  'can_track',actor.id=c.operator_id AND coalesce(assigned,c.operator_id)=actor.id,
  'can_edit',actor.id<>h.user_id AND (actor.role='admin' OR (coalesce(assigned,c.operator_id) IS NULL OR coalesce(assigned,c.operator_id)=actor.id)),
  'events',coalesce((SELECT jsonb_agg(jsonb_build_object('at',e.created_at,'actor_id',e.actor_id,
    'action',e.payload->>'action','arrival_position',e.payload->'arrival_position','snapshot',e.snapshot) ORDER BY e.id DESC)
    FROM trujillo.sos_case_events e WHERE e.case_id=p_id),'[]'::jsonb));
END; $$;

CREATE OR REPLACE FUNCTION trujillo.sos_case_update(p_id uuid,p_request uuid,p_version integer,p_data jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor trujillo.users; h trujillo.help_requests; c trujillo.sos_cases; assigned uuid;
 old_payload jsonb; op text:=p_data->>'action'; new_incident uuid;
BEGIN
 SELECT * INTO actor FROM trujillo.users WHERE id=trujillo.current_actor(true);
 -- Same lock order as call_action: simultaneous accept/evaluate cannot steal ownership.
 PERFORM pg_advisory_xact_lock(360017);
 SELECT * INTO h FROM trujillo.help_requests WHERE id=p_id AND source='sos' FOR UPDATE;
 IF h.id IS NULL THEN RAISE EXCEPTION 'SOS no disponible' USING ERRCODE='P0002'; END IF;
 IF actor.id=h.user_id THEN RAISE EXCEPTION 'No puedes evaluar tu propio SOS' USING ERRCODE='42501'; END IF;
 SELECT operator_id INTO assigned FROM trujillo.call_sessions WHERE id=p_id;
 SELECT * INTO c FROM trujillo.sos_cases WHERE id=p_id FOR UPDATE;
 IF actor.role<>'admin' AND coalesce(assigned,c.operator_id,actor.id)<>actor.id THEN
  RAISE EXCEPTION 'Otro operador atiende el caso' USING ERRCODE='42501'; END IF;
 SELECT payload INTO old_payload FROM trujillo.sos_case_events WHERE case_id=p_id AND request_id=p_request;
 IF old_payload IS NOT NULL THEN
  IF old_payload<>p_data THEN RAISE EXCEPTION 'Reintento diferente'; END IF;
  RETURN trujillo.sos_case_read(p_id);
 END IF;
 IF p_version IS DISTINCT FROM coalesce(c.version,0) THEN RAISE EXCEPTION 'Caso actualizado por otra sesión'; END IF;
 IF op IS NULL OR op NOT IN ('pending','confirm','discard','en_route','on_scene','resolve','save','support','support_clear')
 OR p_request IS NULL OR p_data->>'category' NOT IN ('Robo','Auxilio','Agresión','Riesgo')
 OR NOT ((p_data->>'latitude')::double precision BETWEEN -90 AND 90)
 OR NOT ((p_data->>'longitude')::double precision BETWEEN -180 AND 180)
 OR length(coalesce(p_data->>'internal_note',''))>2000
 OR length(coalesce(p_data->>'public_description',''))>500
 OR length(coalesce(p_data->>'place',''))>100 THEN
  RAISE EXCEPTION 'Datos inválidos' USING ERRCODE='22023'; END IF;
 IF c.attention='resolved' OR c.decision='discarded' THEN RAISE EXCEPTION 'Caso cerrado'; END IF;
 IF op IN ('pending','discard') AND c.incident_id IS NOT NULL THEN RAISE EXCEPTION 'Incidente ya confirmado'; END IF;
 IF op IN ('en_route','on_scene','resolve') AND c.decision IS DISTINCT FROM 'confirmed' THEN
  RAISE EXCEPTION 'Confirma primero el incidente'; END IF;
 IF op='en_route' AND c.attention NOT IN ('none','en_route') THEN RAISE EXCEPTION 'Transición inválida'; END IF;
 IF op='on_scene' AND c.attention NOT IN ('none','en_route','on_scene') THEN RAISE EXCEPTION 'Transición inválida'; END IF;
 IF op='on_scene' AND NOT EXISTS(SELECT 1 FROM trujillo.sos_arrival_samples WHERE case_id=p_id AND actor_id=actor.id AND ready_at>clock_timestamp()-interval '30 seconds') THEN RAISE EXCEPTION 'Llegada requiere GPS comprobado' USING ERRCODE='42501'; END IF;
 IF op='resolve' AND length(trim(coalesce(p_data->>'outcome','')))<5 THEN
  RAISE EXCEPTION 'Resultado requerido' USING ERRCODE='22023'; END IF;
 IF op IN ('pending','discard') AND length(trim(coalesce(p_data->>'internal_note','')))<5 THEN
  RAISE EXCEPTION 'Motivo requerido' USING ERRCODE='22023'; END IF;

 INSERT INTO trujillo.sos_cases(id,operator_id,category,latitude,longitude)
 VALUES(p_id,actor.id,p_data->>'category',(p_data->>'latitude')::double precision,(p_data->>'longitude')::double precision)
 ON CONFLICT(id) DO NOTHING;
 UPDATE trujillo.sos_cases SET version=version+1,
 support_requested=CASE WHEN op='support' THEN true WHEN op IN ('support_clear','resolve','discard') THEN false ELSE support_requested END,
 category=p_data->>'category',latitude=(p_data->>'latitude')::double precision,longitude=(p_data->>'longitude')::double precision,
 place=p_data->>'place',public_description=p_data->>'public_description',internal_note=p_data->>'internal_note',
 outcome=coalesce(p_data->>'outcome',''),updated_at=now(),
 decision=CASE op WHEN 'confirm' THEN 'confirmed' WHEN 'discard' THEN 'discarded' WHEN 'pending' THEN 'pending' ELSE decision END,
 attention=CASE WHEN op='confirm' AND attention='none' THEN 'en_route' WHEN op='en_route' THEN 'en_route' WHEN op='on_scene' THEN 'on_scene' WHEN op='resolve' THEN 'resolved' ELSE attention END
 WHERE id=p_id RETURNING * INTO c;
 IF c.decision='confirmed' THEN
  IF c.incident_id IS NULL THEN
   INSERT INTO trujillo.incidents(category,location,occurred_at,status,needs_review,was_public,public_description,public_place,attention)
   VALUES(c.category,extensions.ST_SetSRID(extensions.ST_MakePoint(c.longitude,c.latitude),4326)::extensions.geography,
    h.received_at,'verified',false,true,c.public_description,c.place,c.attention) RETURNING id INTO new_incident;
   UPDATE trujillo.sos_cases SET incident_id=new_incident WHERE id=p_id RETURNING * INTO c;
   INSERT INTO trujillo.reviews(incident_id,reviewer_id,decision,reason)
    VALUES(new_incident,actor.id,'verified','Confirmado por evaluación de SOS');
  ELSE
   UPDATE trujillo.incidents SET category=c.category,
    location=extensions.ST_SetSRID(extensions.ST_MakePoint(c.longitude,c.latitude),4326)::extensions.geography,
    public_description=c.public_description,public_place=c.place,attention=c.attention,
    status=CASE WHEN op='resolve' THEN 'closed' ELSE 'verified' END,needs_review=false,updated_at=now()
    WHERE id=c.incident_id;
   IF op='resolve' THEN INSERT INTO trujillo.reviews(incident_id,reviewer_id,decision,reason)
    VALUES(c.incident_id,actor.id,'closed','Atención SOS finalizada'); END IF;
  END IF;
 END IF;
 UPDATE trujillo.help_requests SET stage=CASE WHEN op='discard' THEN 'Descartada'
 WHEN op='resolve' THEN 'Cerrada' ELSE 'En revisión' END WHERE id=p_id;
 -- Internal notes and optional arrival GPS live ONLY in this operator audit table.
 INSERT INTO trujillo.sos_case_events(case_id,actor_id,request_id,payload,snapshot)
 VALUES(p_id,actor.id,p_request,p_data,to_jsonb(c));
 IF op<>'on_scene' THEN
  DELETE FROM trujillo.sos_arrival_samples WHERE case_id=p_id;
 END IF;
 RETURN trujillo.sos_case_read(p_id);
END; $$;

CREATE FUNCTION trujillo.sos_arrival_check(p_id uuid,p_lat double precision,p_lng double precision,
 p_accuracy double precision,p_observed timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; c trujillo.sos_cases; assigned uuid; sample trujillo.sos_arrival_samples;
 now_at timestamptz:=clock_timestamp(); inside boolean;
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
 inside:=extensions.ST_DWithin(
  extensions.ST_SetSRID(extensions.ST_MakePoint(p_lng,p_lat),4326)::extensions.geography,
  extensions.ST_SetSRID(extensions.ST_MakePoint(c.longitude,c.latitude),4326)::extensions.geography,50);
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

-- Existing confirmed cases adopt the same dispatch semantics, with a private audit.
DO $$
DECLARE c trujillo.sos_cases;
BEGIN
 FOR c IN UPDATE trujillo.sos_cases SET attention='en_route',version=version+1,updated_at=now()
  WHERE decision='confirmed' AND attention='none' RETURNING * LOOP
  UPDATE trujillo.incidents SET attention='en_route',updated_at=now() WHERE id=c.incident_id;
  INSERT INTO trujillo.sos_case_events(case_id,actor_id,request_id,payload,snapshot)
   VALUES(c.id,c.operator_id,gen_random_uuid(),jsonb_build_object('action','en_route','source','migration_022'),to_jsonb(c));
 END LOOP;
END; $$;

