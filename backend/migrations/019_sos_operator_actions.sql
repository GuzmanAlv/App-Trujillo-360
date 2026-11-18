-- SOS presentation, support requests and consent-based return calls.
ALTER TABLE trujillo.sos_cases ADD COLUMN support_requested boolean NOT NULL DEFAULT false;
ALTER TABLE trujillo.call_sessions ADD COLUMN direction text NOT NULL DEFAULT 'citizen' CHECK(direction IN ('citizen','operator'));
ALTER TABLE trujillo.call_sessions ADD COLUMN generation uuid NOT NULL DEFAULT gen_random_uuid();

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
 attention=CASE op WHEN 'en_route' THEN 'en_route' WHEN 'on_scene' THEN 'on_scene' WHEN 'resolve' THEN 'resolved' ELSE attention END
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
 RETURN trujillo.sos_case_read(p_id);
END; $$;

CREATE OR REPLACE FUNCTION trujillo.list_help(p_operator boolean DEFAULT false) RETURNS SETOF jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid;
BEGIN
 actor:=trujillo.current_actor(p_operator);
 RETURN QUERY SELECT (to_jsonb(h)-'user_id'-'submitted_priority') || jsonb_build_object('sos_case',CASE WHEN p_operator AND h.source='sos' THEN
 (SELECT jsonb_build_object('decision',c.decision,'attention',c.attention,'support_requested',c.support_requested) FROM trujillo.sos_cases c WHERE c.id=h.id) ELSE NULL END,
 'call_state',(SELECT state FROM trujillo.call_sessions WHERE id=h.id),'events',
 COALESCE((SELECT jsonb_agg(jsonb_build_object('stage',e.stage,'priority',e.priority,'reason',e.reason,'at',e.created_at) ORDER BY e.id)
 FROM trujillo.help_events e WHERE e.request_id=h.id),'[]'::jsonb))
 FROM trujillo.help_requests h WHERE p_operator OR h.user_id=actor
 ORDER BY (h.stage IN ('Cerrada','Descartada')),CASE h.priority WHEN 'Alta' THEN 0 WHEN 'Media' THEN 1 ELSE 2 END,h.received_at DESC LIMIT 200;
END; $$;

CREATE OR REPLACE FUNCTION trujillo.call_action(p_id uuid,p_action text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; h trujillo.help_requests; c trujillo.call_sessions; is_op boolean;
BEGIN
 actor:=trujillo.current_actor(false);
 SELECT role IN ('operator','admin') INTO is_op FROM trujillo.users WHERE id=actor;
 -- Serializes assignment and busy checks across sessions.
 PERFORM pg_advisory_xact_lock(360017);
 SELECT * INTO h FROM trujillo.help_requests WHERE id=p_id;
 IF NOT FOUND OR h.source<>'sos' OR (h.user_id<>actor AND NOT is_op) THEN
  RAISE EXCEPTION 'No disponible' USING ERRCODE='42501'; END IF;
 UPDATE trujillo.call_sessions SET state=CASE WHEN state='waiting' THEN 'unanswered' ELSE 'ended' END,
 ended_at=now() WHERE state IN ('waiting','accepted') AND expires_at<=now();
 IF p_action='start' THEN
  IF h.user_id<>actor OR h.stage IN ('Cerrada','Descartada') THEN
   RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501'; END IF;
  IF NOT EXISTS(SELECT 1 FROM trujillo.call_sessions WHERE id=p_id) THEN
   IF EXISTS(SELECT 1 FROM trujillo.call_sessions WHERE state IN ('waiting','accepted') AND (citizen_id=actor OR operator_id=actor)) THEN
    RAISE EXCEPTION 'Ya hay una llamada activa' USING ERRCODE='P0001'; END IF;
   INSERT INTO trujillo.call_sessions(id,citizen_id) VALUES(p_id,actor);
   INSERT INTO trujillo.help_events(request_id,actor_id,stage,priority,reason)
   VALUES(p_id,actor,h.stage,h.priority,'Solicitud de llamada de voz creada.');
  END IF;
 END IF;
 SELECT * INTO c FROM trujillo.call_sessions WHERE id=p_id FOR UPDATE;
 IF p_action='callback' THEN
  IF NOT is_op OR actor=h.user_id OR NOT (EXISTS(SELECT 1 FROM trujillo.sos_cases WHERE id=p_id AND operator_id=actor) OR c.operator_id=actor OR (c.operator_id IS NULL AND NOT EXISTS(SELECT 1 FROM trujillo.sos_cases WHERE id=p_id)))
  THEN RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501'; END IF;
  IF c.id IS NULL THEN RAISE EXCEPTION 'Sin llamada anterior'; END IF;
  IF h.stage IN ('Cerrada','Descartada') THEN RAISE EXCEPTION 'Caso cerrado'; END IF;
  IF c.state IN ('waiting','accepted') AND c.expires_at>now() THEN
   IF c.direction<>'operator' OR c.operator_id<>actor THEN RAISE EXCEPTION 'Llamada activa'; END IF;
  ELSE
   IF EXISTS(SELECT 1 FROM trujillo.call_sessions WHERE id<>p_id AND state IN ('waiting','accepted') AND expires_at>now()
    AND (citizen_id IN (actor,h.user_id) OR operator_id IN (actor,h.user_id))) THEN RAISE EXCEPTION 'Participante ocupado'; END IF;
   UPDATE trujillo.call_sessions SET direction='operator',generation=gen_random_uuid(),state='waiting',operator_id=actor,
    created_at=now(),accepted_at=NULL,ended_at=NULL,expires_at=now()+interval '90 seconds' WHERE id=p_id RETURNING * INTO c;
   INSERT INTO trujillo.help_events(request_id,actor_id,stage,priority,reason)
    VALUES(p_id,actor,h.stage,h.priority,'El operador solicita devolver la llamada.');
  END IF;
 END IF;
 IF p_action='answer' THEN
  IF actor<>c.citizen_id OR c.direction<>'operator' THEN RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501'; END IF;
  IF c.state='waiting' AND c.expires_at>now() THEN
   UPDATE trujillo.call_sessions SET state='accepted',accepted_at=now(),expires_at=now()+interval '30 minutes' WHERE id=p_id RETURNING * INTO c;
  ELSIF c.state<>'accepted' THEN RAISE EXCEPTION 'Llamada terminada'; END IF;
 END IF;

 IF NOT FOUND THEN RAISE EXCEPTION 'Sin llamada' USING ERRCODE='P0002'; END IF;
 IF p_action='accept' THEN
  IF c.direction='operator' THEN RAISE EXCEPTION 'Debe responder el ciudadano'; END IF;
  IF EXISTS(SELECT 1 FROM trujillo.sos_cases WHERE id=p_id AND operator_id<>actor) THEN RAISE EXCEPTION 'Caso asignado a otro operador'; END IF;
  IF NOT is_op OR actor=c.citizen_id THEN RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501'; END IF;
  IF c.state='waiting' AND h.stage NOT IN ('Cerrada','Descartada') THEN
   IF EXISTS(SELECT 1 FROM trujillo.call_sessions WHERE id<>p_id AND state IN ('waiting','accepted') AND (operator_id=actor OR citizen_id=actor)) THEN
    RAISE EXCEPTION 'Operador ocupado' USING ERRCODE='P0001'; END IF;
   UPDATE trujillo.call_sessions SET operator_id=actor,state='accepted',accepted_at=now(),expires_at=now()+interval '30 minutes' WHERE id=p_id RETURNING * INTO c;
   UPDATE trujillo.help_requests SET stage='En revisión' WHERE id=p_id AND stage='Recibida';
   INSERT INTO trujillo.help_events(request_id,actor_id,stage,priority,reason)
   VALUES(p_id,actor,'En revisión',h.priority,'Operador aceptó la llamada. Conexión de audio pendiente.');
  ELSIF c.state<>'accepted' OR c.operator_id<>actor THEN
   RAISE EXCEPTION 'Llamada no disponible' USING ERRCODE='P0001';
  END IF;
 ELSIF p_action='end' THEN
  IF actor<>c.citizen_id AND actor IS DISTINCT FROM c.operator_id THEN
   RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501'; END IF;
  IF c.state IN ('waiting','accepted') THEN
   UPDATE trujillo.call_sessions SET state='ended',ended_at=now() WHERE id=p_id RETURNING * INTO c;
   INSERT INTO trujillo.help_events(request_id,actor_id,stage,priority,reason)
   VALUES(p_id,actor,h.stage,h.priority,'Llamada finalizada o cancelada. La solicitud de ayuda sigue disponible.');
  END IF;
 ELSIF p_action NOT IN ('start','status','token','callback','answer') THEN
  RAISE EXCEPTION 'Acción inválida' USING ERRCODE='22023';
 END IF;
 IF p_action='token' AND (c.state<>'accepted' OR (actor<>c.citizen_id AND actor IS DISTINCT FROM c.operator_id)) THEN
  RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501'; END IF;
 RETURN jsonb_build_object('id',c.id,'state',c.state,'expires_at',c.expires_at,
  'can_join',c.state='accepted' AND (actor=c.citizen_id OR actor=c.operator_id),
  'room','sos-'||c.id::text||'-'||c.generation::text,'participant',actor::text);
END; $$;

CREATE FUNCTION trujillo.return_calls() RETURNS SETOF jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid;
BEGIN
 actor:=trujillo.current_actor(false);
 RETURN QUERY SELECT jsonb_build_object('id',id,'created_at',created_at,'expires_at',expires_at,'callback',true)
 FROM trujillo.call_sessions WHERE citizen_id=actor AND direction='operator' AND state='waiting' AND expires_at>now();
END; $$;
REVOKE ALL ON FUNCTION trujillo.return_calls() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION trujillo.return_calls() TO trujillo_api;

CREATE OR REPLACE FUNCTION trujillo.incoming_calls() RETURNS SETOF jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor trujillo.users;
BEGIN
 SELECT * INTO actor FROM trujillo.users WHERE id=trujillo.current_actor(true);
 IF EXISTS(SELECT 1 FROM trujillo.call_sessions WHERE state='accepted' AND expires_at>now()
 AND (operator_id=actor.id OR citizen_id=actor.id)) THEN RETURN; END IF;
 RETURN QUERY SELECT jsonb_build_object('id',c.id,'created_at',c.created_at,'expires_at',c.expires_at)
 FROM trujillo.call_sessions c JOIN trujillo.help_requests h ON h.id=c.id
 WHERE c.direction='citizen' AND NOT EXISTS(SELECT 1 FROM trujillo.sos_cases sc WHERE sc.id=c.id AND sc.operator_id<>actor.id) AND c.state='waiting' AND c.expires_at>now() AND c.citizen_id<>actor.id
 AND h.stage NOT IN ('Cerrada','Descartada') ORDER BY c.created_at LIMIT 10;
END; $$;
