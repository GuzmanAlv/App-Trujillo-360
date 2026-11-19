-- Private operator case; caller coordinates are never overwritten or published.
CREATE TABLE trujillo.sos_cases (
 id uuid PRIMARY KEY REFERENCES trujillo.help_requests(id),
 operator_id uuid NOT NULL REFERENCES trujillo.users(id),
 incident_id uuid UNIQUE REFERENCES trujillo.incidents(id),
 version integer NOT NULL DEFAULT 0,
 decision text NOT NULL DEFAULT 'pending' CHECK(decision IN ('pending','confirmed','discarded')),
 attention text NOT NULL DEFAULT 'none' CHECK(attention IN ('none','en_route','on_scene','resolved')),
 category text NOT NULL CHECK(category IN ('Robo','Auxilio','Agresión','Riesgo')),
 latitude double precision NOT NULL CHECK(latitude BETWEEN -90 AND 90),
 longitude double precision NOT NULL CHECK(longitude BETWEEN -180 AND 180),
 place text NOT NULL DEFAULT '', public_description text NOT NULL DEFAULT '',
 internal_note text NOT NULL DEFAULT '', outcome text NOT NULL DEFAULT '',
 updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE trujillo.sos_case_events (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 case_id uuid NOT NULL REFERENCES trujillo.sos_cases(id),
 actor_id uuid NOT NULL REFERENCES trujillo.users(id),
 request_id uuid NOT NULL,
 payload jsonb NOT NULL,
 snapshot jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(case_id,request_id)
);
ALTER TABLE trujillo.incidents ADD COLUMN public_description text NOT NULL DEFAULT '';
ALTER TABLE trujillo.incidents ADD COLUMN public_place text NOT NULL DEFAULT '';
ALTER TABLE trujillo.incidents ADD COLUMN attention text NOT NULL DEFAULT 'none'
 CHECK(attention IN ('none','en_route','on_scene','resolved'));
ALTER TABLE trujillo.sos_cases ENABLE ROW LEVEL SECURITY;
ALTER TABLE trujillo.sos_case_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON trujillo.sos_cases,trujillo.sos_case_events FROM PUBLIC,anon,authenticated,trujillo_api;

CREATE FUNCTION trujillo.sos_case_read(p_id uuid) RETURNS jsonb
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
  'decision',coalesce(c.decision,'pending'),'attention',coalesce(c.attention,'none'),
  'category',coalesce(c.category,h.category),'latitude',coalesce(c.latitude,h.latitude),
  'longitude',coalesce(c.longitude,h.longitude),'place',coalesce(c.place,''),
  'public_description',coalesce(c.public_description,''),'internal_note',coalesce(c.internal_note,''),
  'outcome',coalesce(c.outcome,''),'incident_id',c.incident_id,
  'can_edit',actor.id<>h.user_id AND (actor.role='admin' OR (coalesce(assigned,c.operator_id) IS NULL OR coalesce(assigned,c.operator_id)=actor.id)),
  'events',coalesce((SELECT jsonb_agg(jsonb_build_object('at',e.created_at,'actor_id',e.actor_id,
    'action',e.payload->>'action','arrival_position',e.payload->'arrival_position','snapshot',e.snapshot) ORDER BY e.id DESC)
    FROM trujillo.sos_case_events e WHERE e.case_id=p_id),'[]'::jsonb));
END; $$;

CREATE FUNCTION trujillo.sos_case_update(p_id uuid,p_request uuid,p_version integer,p_data jsonb) RETURNS jsonb
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
 IF op IS NULL OR op NOT IN ('pending','confirm','discard','en_route','on_scene','resolve','save')
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
 IF (op='confirm' OR c.decision='confirmed') AND
 (length(trim(coalesce(p_data->>'public_description','')))<5 OR length(trim(coalesce(p_data->>'place','')))<3) THEN
  RAISE EXCEPTION 'Descripción pública y referencia requeridas' USING ERRCODE='22023'; END IF;
 INSERT INTO trujillo.sos_cases(id,operator_id,category,latitude,longitude)
 VALUES(p_id,actor.id,p_data->>'category',(p_data->>'latitude')::double precision,(p_data->>'longitude')::double precision)
 ON CONFLICT(id) DO NOTHING;
 UPDATE trujillo.sos_cases SET version=version+1,
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

CREATE FUNCTION trujillo.incoming_calls() RETURNS SETOF jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor trujillo.users;
BEGIN
 SELECT * INTO actor FROM trujillo.users WHERE id=trujillo.current_actor(true);
 IF EXISTS(SELECT 1 FROM trujillo.call_sessions WHERE state='accepted' AND expires_at>now()
 AND (operator_id=actor.id OR citizen_id=actor.id)) THEN RETURN; END IF;
 RETURN QUERY SELECT jsonb_build_object('id',c.id,'created_at',c.created_at,'expires_at',c.expires_at)
 FROM trujillo.call_sessions c JOIN trujillo.help_requests h ON h.id=c.id
 WHERE c.state='waiting' AND c.expires_at>now() AND c.citizen_id<>actor.id
 AND h.stage NOT IN ('Cerrada','Descartada') ORDER BY c.created_at LIMIT 10;
END; $$;

-- Explicit public allowlist; never serialize sos_cases or caller coordinates here.
CREATE FUNCTION trujillo.public_case_fields(p_ids uuid[]) RETURNS SETOF jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM trujillo.current_actor(false);
 RETURN QUERY SELECT jsonb_build_object('id',i.id,'description',i.public_description,
 'place',nullif(i.public_place,''),'attention',i.attention)
 FROM trujillo.incidents i WHERE i.id=ANY(p_ids)
 AND trujillo.is_public_incident(i.status,i.corroboration_count,i.needs_review)
 AND i.occurred_at>now()-interval '7 days' AND i.occurred_at<=now();
END; $$;
REVOKE ALL ON FUNCTION trujillo.sos_case_read(uuid),trujillo.sos_case_update(uuid,uuid,integer,jsonb),
 trujillo.incoming_calls(),trujillo.public_case_fields(uuid[]) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION trujillo.sos_case_read(uuid),trujillo.sos_case_update(uuid,uuid,integer,jsonb),
 trujillo.incoming_calls(),trujillo.public_case_fields(uuid[]) TO trujillo_api;

-- Community feed exposes incident summaries, never owners or private photos.
CREATE OR REPLACE FUNCTION trujillo.nearby_incidents(p_lat double precision, p_lng double precision, p_radius integer)
RETURNS TABLE(id uuid, category text, latitude double precision, longitude double precision,
 occurred_at timestamptz, status text, corroboration_count integer, needs_review boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE point extensions.geography;
BEGIN
 IF NOT EXISTS (SELECT 1 FROM trujillo.users u WHERE u.auth_provider='firebase'
 AND u.auth_subject=current_setting('app.firebase_uid',true) AND u.status='active') THEN
 RAISE EXCEPTION 'Cuenta no disponible' USING ERRCODE='42501';
 END IF;
 IF p_lat IS NULL OR p_lng IS NULL OR p_radius IS NULL OR NOT (p_lat BETWEEN -90 AND 90)
 OR NOT (p_lng BETWEEN -180 AND 180) OR NOT (p_radius BETWEEN 100 AND 3000) THEN
 RAISE EXCEPTION 'Coordenadas inválidas' USING ERRCODE='22023';
 END IF;
 point := extensions.ST_SetSRID(extensions.ST_MakePoint(p_lng,p_lat),4326)::extensions.geography;
 RETURN QUERY SELECT i.id,i.category,extensions.ST_Y(i.location::extensions.geometry),
 extensions.ST_X(i.location::extensions.geometry),i.occurred_at,i.status,i.corroboration_count,i.needs_review
 FROM trujillo.incidents i WHERE trujillo.is_public_incident(i.status,i.corroboration_count,i.needs_review)
 AND i.occurred_at > now()-interval '7 days' AND i.occurred_at<=now()
 AND extensions.ST_DWithin(i.location,point,p_radius)
 ORDER BY extensions.ST_Distance(i.location,point),i.id LIMIT 200;
END;
$$;
REVOKE ALL ON FUNCTION trujillo.nearby_incidents(double precision,double precision,integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION trujillo.nearby_incidents(double precision,double precision,integer) TO trujillo_api;

CREATE OR REPLACE FUNCTION trujillo.map_incidents(p_south double precision, p_north double precision,
 p_west double precision, p_east double precision)
RETURNS TABLE(id uuid, category text, latitude double precision, longitude double precision,
 occurred_at timestamptz, status text, corroboration_count integer, needs_review boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM trujillo.users u WHERE u.auth_provider='firebase'
 AND u.auth_subject=current_setting('app.firebase_uid',true) AND u.status='active') THEN
 RAISE EXCEPTION 'Cuenta no disponible' USING ERRCODE='42501'; END IF;
 IF p_south IS NULL OR p_north IS NULL OR p_west IS NULL OR p_east IS NULL
 OR NOT (p_south BETWEEN -90 AND 90) OR NOT (p_north BETWEEN -90 AND 90)
 OR p_south > p_north OR NOT (p_west BETWEEN -180 AND 180) OR NOT (p_east BETWEEN -180 AND 180) THEN
 RAISE EXCEPTION 'Área inválida' USING ERRCODE='22023'; END IF;
 RETURN QUERY SELECT i.id,i.category,extensions.ST_Y(i.location::extensions.geometry),
 extensions.ST_X(i.location::extensions.geometry),i.occurred_at,i.status,i.corroboration_count,i.needs_review
 FROM trujillo.incidents i WHERE trujillo.is_public_incident(i.status,i.corroboration_count,i.needs_review)
 AND i.occurred_at > now()-interval '7 days' AND i.occurred_at<=now()
 AND CASE WHEN p_west <= p_east THEN
 extensions.ST_Intersects(i.location::extensions.geometry,extensions.ST_MakeEnvelope(p_west,p_south,p_east,p_north,4326))
 ELSE
 (extensions.ST_Intersects(i.location::extensions.geometry,extensions.ST_MakeEnvelope(p_west,p_south,180,p_north,4326))
 OR extensions.ST_Intersects(i.location::extensions.geometry,extensions.ST_MakeEnvelope(-180,p_south,p_east,p_north,4326))) END
 ORDER BY i.occurred_at DESC,i.id LIMIT 500;
END;
$$;
REVOKE ALL ON FUNCTION trujillo.map_incidents(double precision,double precision,double precision,double precision) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION trujillo.map_incidents(double precision,double precision,double precision,double precision) TO trujillo_api;


-- Compatible extension of schema 11: old apps ignore the additional place field.
-- Keep schema_version=11 because the deployed API readiness requires exactly 11.
-- No identities or private descriptions are exposed. Apply in one transaction.
DROP FUNCTION trujillo.incident_reports(uuid);
CREATE FUNCTION trujillo.incident_reports(p_incident uuid)
RETURNS TABLE(id uuid, category text, latitude double precision, longitude double precision,
 occurred_at timestamptz, status text, corroboration_count integer, needs_review boolean, place text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM trujillo.users u WHERE u.auth_provider='firebase'
 AND u.auth_subject=current_setting('app.firebase_uid',true) AND u.status='active') THEN
 RAISE EXCEPTION 'Cuenta no disponible' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS (SELECT 1 FROM trujillo.incidents i WHERE i.id=p_incident
 AND trujillo.is_public_incident(i.status,i.corroboration_count,i.needs_review) AND i.occurred_at>now()-interval '7 days' AND i.occurred_at<=now()) THEN
 RAISE EXCEPTION 'Incidente no disponible' USING ERRCODE='P0002'; END IF;
 RETURN QUERY SELECT r.id,r.category,extensions.ST_Y(r.location::extensions.geometry),
 extensions.ST_X(r.location::extensions.geometry),r.occurred_at,i.status,i.corroboration_count,i.needs_review,r.place
 FROM trujillo.reports r JOIN trujillo.incidents i ON i.id=r.incident_id
 WHERE r.incident_id=p_incident AND r.withdrawn_at IS NULL
 ORDER BY r.occurred_at,r.id;
END;
$$;
REVOKE ALL ON FUNCTION trujillo.incident_reports(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION trujillo.incident_reports(uuid) TO trujillo_api;

CREATE OR REPLACE FUNCTION trujillo.update_help(p_id uuid,p_stage text,p_priority text,p_reason text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; old trujillo.help_requests;
BEGIN
 actor:=trujillo.current_actor(true);
 IF EXISTS(SELECT 1 FROM trujillo.help_requests WHERE id=p_id AND source='sos') THEN RAISE EXCEPTION 'Usa evaluación SOS'; END IF;
 SELECT * INTO old FROM trujillo.help_requests WHERE id=p_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'No disponible' USING ERRCODE='P0002'; END IF;
 IF p_stage IS NULL OR p_priority IS NULL OR p_priority NOT IN ('Baja','Media','Alta') OR p_reason IS NULL OR length(trim(p_reason)) NOT BETWEEN 5 AND 500
 OR NOT ((old.stage='Recibida' AND p_stage IN ('En revisión','Descartada'))
 OR (old.stage IN ('En revisión','Acción registrada') AND p_stage IN ('Acción registrada','Cerrada','Descartada')))
 THEN RAISE EXCEPTION 'Transición inválida' USING ERRCODE='22023'; END IF;
 UPDATE trujillo.help_requests SET stage=p_stage,priority=p_priority WHERE id=p_id;
 INSERT INTO trujillo.help_events(request_id,actor_id,stage,priority,reason) VALUES(p_id,actor,p_stage,p_priority,trim(p_reason));
END; $$;

CREATE OR REPLACE FUNCTION trujillo.review_incident(p_id uuid,p_decision text,p_reason text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid;
BEGIN
 actor:=trujillo.current_actor(true);
 IF EXISTS(SELECT 1 FROM trujillo.sos_cases WHERE incident_id=p_id) THEN RAISE EXCEPTION 'Usa evaluación SOS'; END IF;
 IF p_decision IS NULL OR p_decision NOT IN ('verified','discarded','closed') OR p_reason IS NULL OR length(trim(p_reason)) NOT BETWEEN 5 AND 500
 THEN RAISE EXCEPTION 'Decisión inválida' USING ERRCODE='22023'; END IF;
 PERFORM 1 FROM trujillo.incidents WHERE id=p_id AND status IN ('pending','corroborated','verified') FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'No disponible' USING ERRCODE='P0002'; END IF;
 INSERT INTO trujillo.reviews(incident_id,reviewer_id,decision,reason) VALUES(p_id,actor,p_decision,trim(p_reason));
 UPDATE trujillo.incidents SET was_public=was_public OR trujillo.is_public_incident(status,corroboration_count,needs_review),status=p_decision,needs_review=false,updated_at=now() WHERE id=p_id;
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
 IF NOT FOUND THEN RAISE EXCEPTION 'Sin llamada' USING ERRCODE='P0002'; END IF;
 IF p_action='accept' THEN
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
 ELSIF p_action NOT IN ('start','status','token') THEN
  RAISE EXCEPTION 'Acción inválida' USING ERRCODE='22023';
 END IF;
 IF p_action='token' AND (c.state<>'accepted' OR (actor<>c.citizen_id AND actor IS DISTINCT FROM c.operator_id)) THEN
  RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501'; END IF;
 RETURN jsonb_build_object('id',c.id,'state',c.state,'expires_at',c.expires_at,
  'can_join',c.state='accepted' AND (actor=c.citizen_id OR actor=c.operator_id),
  'participant',actor::text);
END; $$;
REVOKE ALL ON FUNCTION trujillo.call_action(uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION trujillo.call_action(uuid,text) TO trujillo_api;

CREATE OR REPLACE FUNCTION trujillo.operator_incidents() RETURNS SETOF jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM trujillo.current_actor(true);
 RETURN QUERY SELECT jsonb_build_object('id',i.id,'category',i.category,'occurred_at',i.occurred_at,'status',i.status,
 'corroboration_count',i.corroboration_count,'needs_review',i.needs_review,'latitude',extensions.ST_Y(i.location::extensions.geometry),
 'longitude',extensions.ST_X(i.location::extensions.geometry),
 'sos_case_id',(SELECT c.id FROM trujillo.sos_cases c WHERE c.incident_id=i.id)) FROM trujillo.incidents i
 WHERE i.status IN ('pending','corroborated','verified') ORDER BY i.created_at DESC LIMIT 200;
END; $$;

CREATE OR REPLACE FUNCTION trujillo.push_target(p_kind text,p_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb;
BEGIN
 PERFORM trujillo.current_actor(p_kind<>'citizen');
 IF p_kind='operator_help' THEN
  SELECT (to_jsonb(h)-'user_id'-'submitted_priority')||jsonb_build_object('events',
   coalesce((SELECT jsonb_agg(jsonb_build_object('stage',e.stage,'priority',e.priority,'reason',e.reason,'at',e.created_at) ORDER BY e.id) FROM trujillo.help_events e WHERE e.request_id=h.id),'[]'::jsonb))
  INTO result FROM trujillo.help_requests h WHERE h.id=p_id;
 ELSIF p_kind IN ('citizen','operator_incident') THEN
  SELECT jsonb_build_object('id',i.id,'category',i.category,'latitude',extensions.ST_Y(i.location::extensions.geometry),
   'longitude',extensions.ST_X(i.location::extensions.geometry),'occurred_at',i.occurred_at,'status',i.status,'corroboration_count',i.corroboration_count,'needs_review',i.needs_review,'description',i.public_description,'place',i.public_place,'attention',i.attention)
  INTO result FROM trujillo.incidents i WHERE i.id=p_id AND (p_kind='operator_incident' OR
   (trujillo.is_public_incident(i.status,i.corroboration_count,i.needs_review) AND i.occurred_at>now()-interval '7 days' AND i.occurred_at<=now()));
 ELSE RAISE EXCEPTION 'Tipo inválido' USING ERRCODE='22023'; END IF;
 IF result IS NULL THEN RAISE EXCEPTION 'Caso no disponible' USING ERRCODE='P0002'; END IF;
 IF p_kind='operator_incident' THEN result:=result||jsonb_build_object('sos_case_id',(SELECT c.id FROM trujillo.sos_cases c WHERE c.incident_id=p_id)); END IF;
 RETURN result;
END; $$;
