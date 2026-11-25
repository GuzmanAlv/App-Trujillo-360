-- Discard while en route; assigned operators may suspend the citizen with a recorded reason.
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
 IF op IS NULL OR op NOT IN ('pending','confirm','discard','discard_block','en_route','on_scene','resolve','save','support','support_clear')
 OR p_request IS NULL OR p_data->>'category' NOT IN ('Robo','Auxilio','Agresión','Riesgo')
 OR NOT ((p_data->>'latitude')::double precision BETWEEN -90 AND 90)
 OR NOT ((p_data->>'longitude')::double precision BETWEEN -180 AND 180)
 OR length(coalesce(p_data->>'internal_note',''))>2000
 OR length(coalesce(p_data->>'public_description',''))>500
 OR length(coalesce(p_data->>'place',''))>100 THEN
  RAISE EXCEPTION 'Datos inválidos' USING ERRCODE='22023'; END IF;
 IF c.attention='resolved' OR c.decision='discarded' THEN RAISE EXCEPTION 'Caso cerrado'; END IF;
 IF op='pending' AND c.incident_id IS NOT NULL THEN RAISE EXCEPTION 'Incidente ya confirmado'; END IF;

 IF op IN ('en_route','on_scene','resolve') AND c.decision IS DISTINCT FROM 'confirmed' THEN
  RAISE EXCEPTION 'Confirma primero el incidente'; END IF;
 IF op='en_route' AND c.attention NOT IN ('none','en_route') THEN RAISE EXCEPTION 'Transición inválida'; END IF;
 IF op='on_scene' AND c.attention NOT IN ('none','en_route','on_scene') THEN RAISE EXCEPTION 'Transición inválida'; END IF;
 IF op='on_scene' AND NOT EXISTS(SELECT 1 FROM trujillo.sos_arrival_samples WHERE case_id=p_id AND actor_id=actor.id AND ready_at>clock_timestamp()-interval '30 seconds') THEN RAISE EXCEPTION 'Llegada requiere GPS comprobado' USING ERRCODE='42501'; END IF;
 IF op='discard_block' AND NOT EXISTS(SELECT 1 FROM trujillo.users WHERE id=h.user_id AND role='citizen') THEN
  RAISE EXCEPTION 'Solo se pueden suspender cuentas ciudadanas desde un SOS' USING ERRCODE='42501'; END IF;
 IF op='resolve' AND length(trim(coalesce(p_data->>'outcome','')))<5 THEN
  RAISE EXCEPTION 'Resultado requerido' USING ERRCODE='22023'; END IF;
 IF op IN ('pending','discard','discard_block') AND length(trim(coalesce(p_data->>'internal_note','')))<5 THEN
  RAISE EXCEPTION 'Motivo requerido' USING ERRCODE='22023'; END IF;

 INSERT INTO trujillo.sos_cases(id,operator_id,category,latitude,longitude)
 VALUES(p_id,actor.id,p_data->>'category',(p_data->>'latitude')::double precision,(p_data->>'longitude')::double precision)
 ON CONFLICT(id) DO NOTHING;
 UPDATE trujillo.sos_cases SET version=version+1,
 support_requested=CASE WHEN op='support' THEN true WHEN op IN ('support_clear','resolve','discard','discard_block') THEN false ELSE support_requested END,
 category=p_data->>'category',latitude=(p_data->>'latitude')::double precision,longitude=(p_data->>'longitude')::double precision,
 place=p_data->>'place',public_description=p_data->>'public_description',internal_note=p_data->>'internal_note',
 outcome=coalesce(p_data->>'outcome',''),updated_at=now(),
 decision=CASE op WHEN 'confirm' THEN 'confirmed' WHEN 'discard' THEN 'discarded' WHEN 'discard_block' THEN 'discarded' WHEN 'pending' THEN 'pending' ELSE decision END,
 attention=CASE WHEN op IN ('discard','discard_block') THEN 'resolved' WHEN op='confirm' AND attention='none' THEN 'en_route' WHEN op='en_route' THEN 'en_route' WHEN op='on_scene' THEN 'on_scene' WHEN op='resolve' THEN 'resolved' ELSE attention END
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
 IF op IN ('discard','discard_block') AND c.incident_id IS NOT NULL THEN
  UPDATE trujillo.incidents SET status='discarded',attention='resolved',needs_review=false,updated_at=now() WHERE id=c.incident_id;
  INSERT INTO trujillo.reviews(incident_id,reviewer_id,decision,reason)
   VALUES(c.incident_id,actor.id,'discarded',left(c.internal_note,500));
 END IF;
 UPDATE trujillo.help_requests SET stage=CASE WHEN op IN ('discard','discard_block') THEN 'Descartada'
 WHEN op='resolve' THEN 'Cerrada' ELSE 'En revisión' END WHERE id=p_id;
 IF op='discard_block' THEN
  UPDATE trujillo.users SET status='suspended',suspension_reason='SOS '||p_id::text||': '||left(c.internal_note,1900) WHERE id=h.user_id AND role='citizen';
 END IF;
 IF op IN ('discard','discard_block') THEN
  UPDATE trujillo.call_sessions SET state='ended',ended_at=coalesce(ended_at,now()),expires_at=least(expires_at,now())
   WHERE id=p_id AND state IN ('waiting','accepted');
 END IF;
 -- Internal notes and optional arrival GPS live ONLY in this operator audit table.
 INSERT INTO trujillo.sos_case_events(case_id,actor_id,request_id,payload,snapshot)
 VALUES(p_id,actor.id,p_request,p_data,to_jsonb(c));
 IF op<>'on_scene' THEN
  DELETE FROM trujillo.sos_arrival_samples WHERE case_id=p_id;
 END IF;
 RETURN trujillo.sos_case_read(p_id);
END; $$;

CREATE FUNCTION trujillo.sos_suspension_version() RETURNS integer
LANGUAGE sql IMMUTABLE SET search_path='' AS $$ SELECT 1 $$;
REVOKE ALL ON FUNCTION trujillo.sos_suspension_version() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION trujillo.sos_suspension_version() TO trujillo_api;

