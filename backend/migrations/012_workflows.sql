-- Additive feature version: preserve base version 11 for the deployed API.
CREATE TABLE trujillo.workflow_migrations(version integer PRIMARY KEY);
CREATE TABLE trujillo.operator_invitations(email text PRIMARY KEY, active boolean NOT NULL DEFAULT true);
ALTER TABLE trujillo.users ADD COLUMN auth_email text;
ALTER TABLE trujillo.incidents ADD COLUMN was_public boolean NOT NULL DEFAULT false;
CREATE TABLE trujillo.help_requests(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL REFERENCES trujillo.users(id),
 request_id uuid NOT NULL, category text NOT NULL CHECK(category IN ('Robo','Auxilio','Agresión','Riesgo')),
 place text NOT NULL, description text NOT NULL, latitude double precision NOT NULL, longitude double precision NOT NULL,
 submitted_priority text NOT NULL, priority text NOT NULL CHECK(priority IN ('Baja','Media','Alta')),
 stage text NOT NULL DEFAULT 'Recibida' CHECK(stage IN ('Recibida','En revisión','Acción registrada','Cerrada','Descartada')),
 received_at timestamptz NOT NULL DEFAULT now(), UNIQUE(user_id,request_id));
CREATE TABLE trujillo.help_events(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 request_id uuid NOT NULL REFERENCES trujillo.help_requests(id),
 actor_id uuid NOT NULL REFERENCES trujillo.users(id), stage text NOT NULL, priority text NOT NULL,
 reason text NOT NULL, created_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX help_queue_idx ON trujillo.help_requests(stage,received_at DESC);
CREATE INDEX help_events_request_idx ON trujillo.help_events(request_id,id);
ALTER TABLE trujillo.workflow_migrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE trujillo.operator_invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE trujillo.help_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE trujillo.help_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON trujillo.workflow_migrations,trujillo.operator_invitations,trujillo.help_requests,trujillo.help_events FROM PUBLIC,anon,authenticated,trujillo_api;

CREATE FUNCTION trujillo.sync_identity_email(p_email text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 UPDATE trujillo.users u SET auth_email=lower(p_email),
 role=CASE WHEN u.role='citizen' AND EXISTS(SELECT 1 FROM trujillo.operator_invitations v WHERE v.email=lower(p_email) AND v.active) THEN 'operator' ELSE u.role END
 WHERE u.auth_provider='firebase' AND u.auth_subject=current_setting('app.firebase_uid',true) AND u.status='active';
END; $$;
CREATE FUNCTION trujillo.current_actor(p_operator boolean DEFAULT false) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid;
BEGIN
 SELECT id INTO actor FROM trujillo.users WHERE auth_provider='firebase'
 AND auth_subject=current_setting('app.firebase_uid',true) AND status='active'
 AND (NOT p_operator OR role IN ('operator','admin')) FOR SHARE;
 IF actor IS NULL THEN RAISE EXCEPTION 'Acceso no autorizado' USING ERRCODE='42501'; END IF;
 RETURN actor;
END; $$;
CREATE FUNCTION trujillo.submit_help(p_request uuid,p_category text,p_place text,p_description text,p_lat double precision,p_lng double precision,p_priority text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; old trujillo.help_requests; result trujillo.help_requests;
BEGIN
 actor:=trujillo.current_actor(false);
 IF p_request IS NULL OR p_category IS NULL OR p_category NOT IN ('Robo','Auxilio','Agresión','Riesgo')
 OR p_place IS NULL OR length(trim(p_place)) NOT BETWEEN 3 AND 100 OR p_description IS NULL OR length(p_description)>500
 OR p_lat IS NULL OR NOT(p_lat BETWEEN -90 AND 90) OR p_lng IS NULL OR NOT(p_lng BETWEEN -180 AND 180)
 OR p_priority IS NULL OR p_priority NOT IN ('Baja','Media','Alta') THEN RAISE EXCEPTION 'Datos inválidos' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||p_request::text,0));
 SELECT * INTO old FROM trujillo.help_requests WHERE user_id=actor AND request_id=p_request;
 IF FOUND THEN
  IF (old.category,old.place,old.description,old.latitude,old.longitude,old.submitted_priority)
    IS DISTINCT FROM (p_category,trim(p_place),p_description,p_lat,p_lng,p_priority) THEN
   RAISE EXCEPTION 'Solicitud reutilizada con otros datos' USING ERRCODE='P0001'; END IF;
  RETURN to_jsonb(old)-'user_id';
 END IF;
 INSERT INTO trujillo.help_requests(user_id,request_id,category,place,description,latitude,longitude,submitted_priority,priority)
 VALUES(actor,p_request,p_category,trim(p_place),p_description,p_lat,p_lng,p_priority,p_priority) RETURNING * INTO result;
 INSERT INTO trujillo.help_events(request_id,actor_id,stage,priority,reason)
 VALUES(result.id,actor,'Recibida',p_priority,'Recibida por la plataforma. Aún no confirma revisión ni envío de personal.');
 RETURN to_jsonb(result)-'user_id';
END; $$;
CREATE FUNCTION trujillo.list_help(p_operator boolean DEFAULT false) RETURNS SETOF jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid;
BEGIN
 actor:=trujillo.current_actor(p_operator);
 RETURN QUERY SELECT (to_jsonb(h)-'user_id'-'submitted_priority') || jsonb_build_object('events',
 COALESCE((SELECT jsonb_agg(jsonb_build_object('stage',e.stage,'priority',e.priority,'reason',e.reason,'at',e.created_at) ORDER BY e.id)
 FROM trujillo.help_events e WHERE e.request_id=h.id),'[]'::jsonb))
 FROM trujillo.help_requests h WHERE p_operator OR h.user_id=actor
 ORDER BY (h.stage IN ('Cerrada','Descartada')),CASE h.priority WHEN 'Alta' THEN 0 WHEN 'Media' THEN 1 ELSE 2 END,h.received_at DESC LIMIT 200;
END; $$;
CREATE FUNCTION trujillo.update_help(p_id uuid,p_stage text,p_priority text,p_reason text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; old trujillo.help_requests;
BEGIN
 actor:=trujillo.current_actor(true);
 SELECT * INTO old FROM trujillo.help_requests WHERE id=p_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'No disponible' USING ERRCODE='P0002'; END IF;
 IF p_stage IS NULL OR p_priority IS NULL OR p_priority NOT IN ('Baja','Media','Alta') OR p_reason IS NULL OR length(trim(p_reason)) NOT BETWEEN 5 AND 500
 OR NOT ((old.stage='Recibida' AND p_stage IN ('En revisión','Descartada'))
 OR (old.stage IN ('En revisión','Acción registrada') AND p_stage IN ('Acción registrada','Cerrada','Descartada')))
 THEN RAISE EXCEPTION 'Transición inválida' USING ERRCODE='22023'; END IF;
 UPDATE trujillo.help_requests SET stage=p_stage,priority=p_priority WHERE id=p_id;
 INSERT INTO trujillo.help_events(request_id,actor_id,stage,priority,reason) VALUES(p_id,actor,p_stage,p_priority,trim(p_reason));
END; $$;
CREATE FUNCTION trujillo.operator_incidents() RETURNS SETOF jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM trujillo.current_actor(true);
 RETURN QUERY SELECT jsonb_build_object('id',i.id,'category',i.category,'occurred_at',i.occurred_at,'status',i.status,
 'corroboration_count',i.corroboration_count,'needs_review',i.needs_review,'latitude',extensions.ST_Y(i.location::extensions.geometry),
 'longitude',extensions.ST_X(i.location::extensions.geometry)) FROM trujillo.incidents i
 WHERE i.status IN ('pending','corroborated','verified') ORDER BY i.created_at DESC LIMIT 200;
END; $$;
CREATE FUNCTION trujillo.review_incident(p_id uuid,p_decision text,p_reason text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid;
BEGIN
 actor:=trujillo.current_actor(true);
 IF p_decision IS NULL OR p_decision NOT IN ('verified','discarded','closed') OR p_reason IS NULL OR length(trim(p_reason)) NOT BETWEEN 5 AND 500
 THEN RAISE EXCEPTION 'Decisión inválida' USING ERRCODE='22023'; END IF;
 PERFORM 1 FROM trujillo.incidents WHERE id=p_id AND status IN ('pending','corroborated','verified') FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'No disponible' USING ERRCODE='P0002'; END IF;
 INSERT INTO trujillo.reviews(incident_id,reviewer_id,decision,reason) VALUES(p_id,actor,p_decision,trim(p_reason));
 UPDATE trujillo.incidents SET was_public=was_public OR trujillo.is_public_incident(status,corroboration_count,needs_review),status=p_decision,needs_review=false,updated_at=now() WHERE id=p_id;
END; $$;
-- One shared publication predicate: manually reviewed OR community corroborated.
CREATE FUNCTION trujillo.is_public_incident(p_status text,p_count integer,p_review boolean) RETURNS boolean
LANGUAGE sql IMMUTABLE SET search_path='' AS $$ SELECT NOT p_review AND (p_status='verified' OR (p_status='corroborated' AND p_count>=3)) $$;
CREATE FUNCTION trujillo.incident_density(p_south double precision,p_north double precision,p_west double precision,p_east double precision,p_hour integer DEFAULT -1)
RETURNS TABLE(latitude double precision,longitude double precision,incident_count bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM trujillo.current_actor(false);
 IF p_south IS NULL OR p_north IS NULL OR p_west IS NULL OR p_east IS NULL OR NOT(p_south BETWEEN -90 AND 90) OR NOT(p_north BETWEEN -90 AND 90)
 OR p_south>p_north OR NOT(p_west BETWEEN -180 AND 180) OR NOT(p_east BETWEEN -180 AND 180) OR p_hour IS NULL OR p_hour NOT BETWEEN -1 AND 3 THEN
 RAISE EXCEPTION 'Área inválida' USING ERRCODE='22023'; END IF;
 RETURN QUERY SELECT (floor(extensions.ST_Y(i.location::extensions.geometry)/.001)+.5)*.001,
 (floor(extensions.ST_X(i.location::extensions.geometry)/.001)+.5)*.001,count(*) FROM trujillo.incidents i
 WHERE (trujillo.is_public_incident(i.status,i.corroboration_count,i.needs_review) OR
 (i.status='closed' AND (i.was_public OR EXISTS(SELECT 1 FROM trujillo.reviews r WHERE r.incident_id=i.id AND r.decision='verified'))))
 AND i.occurred_at>now()-interval '90 days' AND i.occurred_at<=now()
 AND (p_hour=-1 OR floor(extract(hour FROM i.occurred_at AT TIME ZONE 'America/Lima')/6)=p_hour)
 AND extensions.ST_Y(i.location::extensions.geometry) BETWEEN p_south AND p_north
 AND ((p_west<=p_east AND extensions.ST_X(i.location::extensions.geometry) BETWEEN p_west AND p_east)
 OR (p_west>p_east AND (extensions.ST_X(i.location::extensions.geometry)>=p_west OR extensions.ST_X(i.location::extensions.geometry)<=p_east)))
 GROUP BY 1,2 ORDER BY count(*) DESC,1,2 LIMIT 1000;
END; $$;
REVOKE ALL ON FUNCTION trujillo.sync_identity_email(text),trujillo.current_actor(boolean),trujillo.submit_help(uuid,text,text,text,double precision,double precision,text),
 trujillo.list_help(boolean),trujillo.update_help(uuid,text,text,text),trujillo.operator_incidents(),trujillo.review_incident(uuid,text,text),
 trujillo.is_public_incident(text,integer,boolean),trujillo.incident_density(double precision,double precision,double precision,double precision,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION trujillo.sync_identity_email(text),trujillo.submit_help(uuid,text,text,text,double precision,double precision,text),
 trujillo.list_help(boolean),trujillo.update_help(uuid,text,text,text),trujillo.operator_incidents(),trujillo.review_incident(uuid,text,text),
 trujillo.incident_density(double precision,double precision,double precision,double precision,integer) TO trujillo_api;
INSERT INTO trujillo.workflow_migrations VALUES(1);
CREATE FUNCTION trujillo.operator_incident_reports(p_id uuid) RETURNS SETOF jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM trujillo.current_actor(true);
 RETURN QUERY SELECT jsonb_build_object('id',r.id,'place',r.place,'description',r.description,'occurred_at',r.occurred_at,
 'photos',COALESCE((SELECT jsonb_agg(p.id ORDER BY p.position) FROM trujillo.report_photos p WHERE p.report_id=r.id),'[]'::jsonb))
 FROM trujillo.reports r WHERE r.incident_id=p_id AND r.withdrawn_at IS NULL ORDER BY r.occurred_at LIMIT 50;
END; $$;
CREATE FUNCTION trujillo.operator_photo(p_incident uuid,p_photo uuid) RETURNS bytea
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE content bytea;
BEGIN
 PERFORM trujillo.current_actor(true);
 SELECT p.content INTO content FROM trujillo.report_photos p JOIN trujillo.reports r ON r.id=p.report_id
 WHERE p.id=p_photo AND r.incident_id=p_incident AND r.withdrawn_at IS NULL;
 IF content IS NULL THEN RAISE EXCEPTION 'No disponible' USING ERRCODE='P0002'; END IF;
 RETURN content;
END; $$;
REVOKE ALL ON FUNCTION trujillo.operator_incident_reports(uuid),trujillo.operator_photo(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION trujillo.operator_incident_reports(uuid),trujillo.operator_photo(uuid,uuid) TO trujillo_api;
