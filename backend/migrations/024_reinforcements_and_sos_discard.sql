-- Re-evaluation after verified arrival keeps the original incident and audit.
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
 IF op='pending' AND c.incident_id IS NOT NULL THEN RAISE EXCEPTION 'Incidente ya confirmado'; END IF;
 IF op='discard' AND c.incident_id IS NOT NULL AND c.attention IS DISTINCT FROM 'on_scene' THEN
  RAISE EXCEPTION 'Descartar tras confirmar requiere llegada al lugar'; END IF;
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
 attention=CASE WHEN op='discard' THEN 'resolved' WHEN op='confirm' AND attention='none' THEN 'en_route' WHEN op='en_route' THEN 'en_route' WHEN op='on_scene' THEN 'on_scene' WHEN op='resolve' THEN 'resolved' ELSE attention END
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
 IF op='discard' AND c.incident_id IS NOT NULL THEN
  UPDATE trujillo.incidents SET status='discarded',attention='resolved',needs_review=false,updated_at=now() WHERE id=c.incident_id;
  INSERT INTO trujillo.reviews(incident_id,reviewer_id,decision,reason)
   VALUES(c.incident_id,actor.id,'discarded',left(c.internal_note,500));
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

CREATE TABLE trujillo.reinforcements (
 id uuid PRIMARY KEY, operator_id uuid NOT NULL REFERENCES trujillo.users(id),
 latitude double precision NOT NULL CHECK(latitude BETWEEN -90 AND 90),
 longitude double precision NOT NULL CHECK(longitude BETWEEN -180 AND 180),
 accuracy double precision NOT NULL CHECK(accuracy BETWEEN 0 AND 100),
 observed_at timestamptz NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(), expires_at timestamptz NOT NULL,
 resolved_at timestamptz
);
CREATE UNIQUE INDEX reinforcements_one_active ON trujillo.reinforcements(operator_id) WHERE resolved_at IS NULL;
ALTER TABLE trujillo.reinforcements ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON trujillo.reinforcements FROM PUBLIC,anon,authenticated,trujillo_api;

CREATE FUNCTION trujillo.reinforcement_list(p_id uuid DEFAULT NULL) RETURNS SETOF jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid;
BEGIN
 actor:=trujillo.current_actor(true);
 RETURN QUERY SELECT jsonb_build_object('id',r.id,'latitude',r.latitude,'longitude',r.longitude,
  'is_mine',r.operator_id=actor,'name',u.display_name,'created_at',r.created_at,'updated_at',r.updated_at)
 FROM trujillo.reinforcements r JOIN trujillo.users u ON u.id=r.operator_id
 WHERE r.resolved_at IS NULL AND r.expires_at>now() AND u.status='active'
 AND (p_id IS NULL OR r.id=p_id) ORDER BY r.created_at DESC LIMIT 100;
END; $$;

CREATE FUNCTION trujillo.reinforcement_request(p_id uuid,p_lat double precision,p_lng double precision,p_accuracy double precision,p_observed timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; existing trujillo.reinforcements;
BEGIN
 actor:=trujillo.current_actor(true);
 IF p_id IS NULL OR p_lat IS NULL OR p_lng IS NULL OR p_accuracy IS NULL OR p_observed IS NULL
 OR NOT(p_lat BETWEEN -90 AND 90 AND p_lng BETWEEN -180 AND 180 AND p_accuracy BETWEEN 0 AND 100)
 OR p_observed<clock_timestamp()-interval '45 seconds' OR p_observed>clock_timestamp()+interval '5 seconds' THEN
  RAISE EXCEPTION 'GPS reciente y preciso requerido' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(actor::text,240));
 SELECT * INTO existing FROM trujillo.reinforcements WHERE id=p_id;
 IF FOUND AND existing.operator_id<>actor THEN RAISE EXCEPTION 'Solicitud no disponible' USING ERRCODE='42501'; END IF;
 IF FOUND AND (existing.resolved_at IS NOT NULL OR existing.expires_at<=now()) THEN RAISE EXCEPTION 'Solicitud cerrada'; END IF;
 UPDATE trujillo.reinforcements SET resolved_at=now() WHERE operator_id=actor AND resolved_at IS NULL AND expires_at<=now();
 SELECT * INTO existing FROM trujillo.reinforcements WHERE operator_id=actor AND resolved_at IS NULL;
 IF NOT FOUND THEN
  INSERT INTO trujillo.reinforcements(id,operator_id,latitude,longitude,accuracy,observed_at,expires_at)
  VALUES(p_id,actor,p_lat,p_lng,p_accuracy,p_observed,now()+interval '15 minutes') RETURNING * INTO existing;
 END IF;
 RETURN (SELECT x FROM trujillo.reinforcement_list(existing.id) x);
END; $$;

CREATE FUNCTION trujillo.reinforcement_position(p_id uuid,p_lat double precision,p_lng double precision,p_accuracy double precision,p_observed timestamptz) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid;
BEGIN
 actor:=trujillo.current_actor(true);
 IF p_lat IS NULL OR p_lng IS NULL OR p_accuracy IS NULL OR p_observed IS NULL
 OR NOT(p_lat BETWEEN -90 AND 90 AND p_lng BETWEEN -180 AND 180 AND p_accuracy BETWEEN 0 AND 100)
 OR p_observed<clock_timestamp()-interval '45 seconds' OR p_observed>clock_timestamp()+interval '5 seconds' THEN
  RAISE EXCEPTION 'GPS reciente y preciso requerido' USING ERRCODE='22023'; END IF;
 UPDATE trujillo.reinforcements SET latitude=p_lat,longitude=p_lng,accuracy=p_accuracy,observed_at=p_observed,
 updated_at=now(),expires_at=now()+interval '15 minutes'
 WHERE id=p_id AND operator_id=actor AND resolved_at IS NULL AND expires_at>now() AND observed_at<=p_observed;
 IF NOT FOUND THEN RAISE EXCEPTION 'Solicitud no disponible' USING ERRCODE='42501'; END IF;
END; $$;

CREATE FUNCTION trujillo.reinforcement_close(p_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 UPDATE trujillo.reinforcements SET resolved_at=coalesce(resolved_at,now())
 WHERE id=p_id AND operator_id=trujillo.current_actor(true);
 IF NOT FOUND THEN RAISE EXCEPTION 'Solicitud no disponible' USING ERRCODE='42501'; END IF;
END; $$;

CREATE FUNCTION trujillo.reinforcement_destination(p_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; result jsonb;
BEGIN
 actor:=trujillo.current_actor(true);
 IF EXISTS(SELECT 1 FROM trujillo.sos_cases c LEFT JOIN trujillo.call_sessions cs ON cs.id=c.id
 WHERE c.operator_id=actor AND coalesce(cs.operator_id,c.operator_id)=actor AND c.decision='confirmed' AND c.attention='en_route') THEN
  RAISE EXCEPTION 'Prioridad del SOS ciudadano'; END IF;
 SELECT x INTO result FROM trujillo.reinforcement_list(p_id) x;
 IF result IS NULL THEN RAISE EXCEPTION 'Solicitud no disponible' USING ERRCODE='P0002'; END IF;
 IF (result->>'is_mine')::boolean THEN RAISE EXCEPTION 'Es tu propia ubicación' USING ERRCODE='42501'; END IF;
 RETURN result;
END; $$;

REVOKE ALL ON FUNCTION trujillo.reinforcement_list(uuid),trujillo.reinforcement_request(uuid,double precision,double precision,double precision,timestamptz),trujillo.reinforcement_position(uuid,double precision,double precision,double precision,timestamptz),trujillo.reinforcement_close(uuid),trujillo.reinforcement_destination(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION trujillo.reinforcement_list(uuid),trujillo.reinforcement_request(uuid,double precision,double precision,double precision,timestamptz),trujillo.reinforcement_position(uuid,double precision,double precision,double precision,timestamptz),trujillo.reinforcement_close(uuid),trujillo.reinforcement_destination(uuid) TO trujillo_api;


ALTER TABLE trujillo.push_outbox DROP CONSTRAINT push_outbox_kind_check;
ALTER TABLE trujillo.push_outbox ADD CONSTRAINT push_outbox_kind_check CHECK(kind IN ('citizen','operator','sos_arrival','sos_callback','reinforcement'));
CREATE FUNCTION trujillo.push_reinforcement() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 INSERT INTO trujillo.push_outbox(device_id,user_id,event_key,kind,target_id,expires_at)
 SELECT d.id,d.user_id,'reinforcement:'||NEW.id::text,'reinforcement',NEW.id,now()+interval '5 minutes'
 FROM trujillo.push_devices d JOIN trujillo.users u ON u.id=d.user_id
 WHERE d.operator_enabled AND d.user_id<>NEW.operator_id AND u.role IN ('operator','admin') AND u.status='active'
 ON CONFLICT(device_id,event_key) DO NOTHING;
 RETURN NEW;
END; $$;
CREATE TRIGGER push_reinforcement AFTER INSERT ON trujillo.reinforcements FOR EACH ROW EXECUTE FUNCTION trujillo.push_reinforcement();

CREATE OR REPLACE FUNCTION trujillo.push_claim() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE job trujillo.push_outbox; recipient record; incident record; report record; payload jsonb;
BEGIN
 SELECT * INTO job FROM trujillo.push_outbox WHERE NOT done AND next_at<=now()
 AND (leased_until IS NULL OR leased_until<now()) ORDER BY CASE WHEN kind='reinforcement' THEN 1 ELSE 0 END,created_at FOR UPDATE SKIP LOCKED LIMIT 1;
 IF NOT FOUND THEN RETURN NULL; END IF;
 SELECT d.*,u.auth_subject,u.role,u.status INTO recipient
 FROM trujillo.push_devices d JOIN trujillo.users u ON u.id=d.user_id
 WHERE d.id=job.device_id AND d.user_id=job.user_id;
 IF NOT FOUND OR recipient.status<>'active' OR job.expires_at<=now() OR job.attempts>=8 THEN
  UPDATE trujillo.push_outbox SET done=true WHERE id=job.id;
  RETURN jsonb_build_object('skipped',true);
 END IF;
 IF job.kind='reinforcement' THEN
  IF NOT recipient.operator_enabled OR recipient.role NOT IN ('operator','admin') OR NOT EXISTS(
   SELECT 1 FROM trujillo.reinforcements r JOIN trujillo.users u ON u.id=r.operator_id WHERE r.id=job.target_id
   AND r.resolved_at IS NULL AND r.expires_at>now() AND r.operator_id<>job.user_id AND u.status='active') THEN
   UPDATE trujillo.push_outbox SET done=true WHERE id=job.id;
   RETURN jsonb_build_object('skipped',true); END IF;
  payload:=jsonb_build_object('kind','reinforcement','target_id',job.target_id::text,'quiet',true,
   'title','Patrulla solicita refuerzos','body','Un operador necesita apoyo. Abre el mapa para ver su ubicación.');
 ELSIF job.kind IN ('sos_arrival','sos_callback') THEN
  IF NOT recipient.sos_enabled OR NOT EXISTS(SELECT 1 FROM trujillo.help_requests h
   WHERE h.id=job.target_id AND h.user_id=job.user_id AND h.source='sos') THEN
   UPDATE trujillo.push_outbox SET done=true WHERE id=job.id;
   RETURN jsonb_build_object('skipped',true); END IF;
  IF (job.kind='sos_arrival' AND NOT EXISTS(SELECT 1 FROM trujillo.sos_cases c WHERE c.id=job.target_id AND c.attention='on_scene'))
   OR (job.kind='sos_callback' AND NOT EXISTS(SELECT 1 FROM trujillo.call_sessions c WHERE c.id=job.target_id
    AND c.state='waiting' AND c.direction='operator' AND c.expires_at>now()
    AND job.event_key='sos-callback:'||c.id::text||':'||c.generation::text)) THEN
   UPDATE trujillo.push_outbox SET done=true WHERE id=job.id;
   RETURN jsonb_build_object('skipped',true); END IF;
  payload:=jsonb_build_object('kind',job.kind,'target_id',job.target_id::text,
   'title',CASE WHEN job.kind='sos_arrival' THEN 'La policía llegó al lugar' ELSE 'El operador te llama' END,
   'body',CASE WHEN job.kind='sos_arrival' THEN 'El operador ya se encuentra en la zona de tu SOS.' ELSE 'Abre Trujillo 360 para contestar la llamada de tu SOS.' END);
 ELSIF job.kind='operator' THEN
  IF NOT recipient.operator_enabled OR recipient.role NOT IN ('operator','admin') THEN
   UPDATE trujillo.push_outbox SET done=true WHERE id=job.id;
   RETURN jsonb_build_object('skipped',true);
  END IF;
  SELECT r.category,r.incident_id,h.id AS help_id INTO report
  FROM trujillo.reports r
  LEFT JOIN trujillo.help_requests h ON h.user_id=r.user_id AND h.request_id=r.request_id
  WHERE r.id=job.target_id AND r.withdrawn_at IS NULL;
  IF FOUND THEN
   payload:=jsonb_build_object('kind','operator',
    'target_id',coalesce(report.help_id,report.incident_id)::text,
    'incident',CASE WHEN report.help_id IS NULL THEN 'true' ELSE 'false' END,
    'title','Nuevo reporte','body',report.category||'. Abre la app para revisar el caso.');
  ELSE
   SELECT h.id AS help_id INTO report FROM trujillo.help_requests h
   WHERE h.id=job.target_id AND h.source='sos' AND h.stage NOT IN ('Cerrada','Descartada');
   IF NOT FOUND THEN
    UPDATE trujillo.push_outbox SET done=true WHERE id=job.id;
    RETURN jsonb_build_object('skipped',true);
   END IF;
   payload:=jsonb_build_object('kind','operator','target_id',report.help_id::text,
    'incident','false','title','SOS · Solicitud de ayuda',
    'body','Una persona compartió su ubicación. Toca para revisar la solicitud.');
  END IF;
 ELSE
  SELECT * INTO incident FROM trujillo.incidents WHERE id=job.target_id;
  IF NOT FOUND OR NOT recipient.citizen_enabled
   OR NOT trujillo.is_public_incident(incident.status,incident.corroboration_count,incident.needs_review)
   OR incident.occurred_at<=now()-interval '7 days' OR incident.occurred_at>now()
   OR (recipient.moving_enabled AND
       (recipient.location_updated_at IS NULL OR recipient.location_updated_at<=now()-interval '20 minutes'))
   OR NOT extensions.ST_DWithin(incident.location,
       extensions.ST_SetSRID(extensions.ST_MakePoint(recipient.longitude,recipient.latitude),4326)::extensions.geography,
       recipient.radius) THEN
   UPDATE trujillo.push_outbox SET done=true WHERE id=job.id;
   RETURN jsonb_build_object('skipped',true);
  END IF;
  payload:=jsonb_build_object('kind','citizen','target_id',incident.id::text,
   'moving',recipient.moving_enabled,'title','Incidente confirmado cerca de ti',
   'body',incident.category||'. Toca para consultar el detalle.');
 END IF;
 IF job.kind='operator' THEN
  payload:=payload||jsonb_build_object('quiet',EXISTS(SELECT 1 FROM trujillo.sos_cases c
   LEFT JOIN trujillo.call_sessions cs ON cs.id=c.id WHERE c.operator_id=job.user_id
   AND coalesce(cs.operator_id,c.operator_id)=job.user_id AND c.decision='confirmed' AND c.attention IN ('en_route','on_scene')));
 END IF;
 job.lease:=gen_random_uuid();
 UPDATE trujillo.push_outbox SET lease=job.lease,leased_until=now()+interval '2 minutes',
  claimed_token=recipient.token,attempts=attempts+1 WHERE id=job.id;
 RETURN payload||jsonb_build_object('job_id',job.id,'lease',job.lease,
  'token',recipient.token,'account_uid',recipient.auth_subject);
END; $$;

