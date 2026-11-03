-- Additive push delivery. No existing incident is announced retroactively.
CREATE TABLE trujillo.push_migrations(version integer PRIMARY KEY);
INSERT INTO trujillo.push_migrations VALUES(1);
CREATE TABLE trujillo.push_devices(
 id uuid PRIMARY KEY, user_id uuid NOT NULL REFERENCES trujillo.users(id),
 token text NOT NULL UNIQUE CHECK(length(token) BETWEEN 20 AND 4096),
 citizen_enabled boolean NOT NULL DEFAULT false, operator_enabled boolean NOT NULL DEFAULT false,
 latitude double precision, longitude double precision, radius integer NOT NULL DEFAULT 500,
 updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK(radius BETWEEN 100 AND 3000),
 CHECK(NOT citizen_enabled OR (latitude BETWEEN -90 AND 90 AND longitude BETWEEN -180 AND 180 AND latitude IS NOT NULL AND longitude IS NOT NULL)));
CREATE TABLE trujillo.push_outbox(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), device_id uuid NOT NULL REFERENCES trujillo.push_devices(id) ON DELETE CASCADE,
 user_id uuid NOT NULL REFERENCES trujillo.users(id), event_key text NOT NULL,
 kind text NOT NULL CHECK(kind IN ('citizen','operator')), target_id uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(), expires_at timestamptz NOT NULL,
 attempts integer NOT NULL DEFAULT 0, next_at timestamptz NOT NULL DEFAULT now(),
 lease uuid, leased_until timestamptz, claimed_token text, done boolean NOT NULL DEFAULT false,
 UNIQUE(device_id,event_key));
CREATE INDEX push_pending ON trujillo.push_outbox(next_at) WHERE NOT done;
ALTER TABLE trujillo.push_migrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE trujillo.push_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE trujillo.push_outbox ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON trujillo.push_migrations,trujillo.push_devices,trujillo.push_outbox FROM PUBLIC,anon,authenticated,trujillo_api;
GRANT SELECT ON trujillo.push_migrations TO trujillo_api;
CREATE POLICY push_version_read ON trujillo.push_migrations FOR SELECT TO trujillo_api USING(true);

CREATE FUNCTION trujillo.push_register(p_id uuid,p_token text,p_citizen boolean,p_operator boolean,p_lat double precision,p_lng double precision,p_radius integer) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; owner uuid;
BEGIN
 actor:=trujillo.current_actor(p_operator);
 IF p_id IS NULL OR p_token IS NULL OR length(p_token) NOT BETWEEN 20 AND 4096
 OR p_citizen IS NULL OR p_operator IS NULL OR p_radius IS NULL OR p_radius NOT BETWEEN 100 AND 3000
 OR (p_lat IS NOT NULL AND NOT(p_lat BETWEEN -90 AND 90)) OR (p_lng IS NOT NULL AND NOT(p_lng BETWEEN -180 AND 180))
 OR (p_citizen AND (p_lat IS NULL OR p_lng IS NULL)) THEN RAISE EXCEPTION 'Datos inválidos' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_token,1));
 SELECT user_id INTO owner FROM trujillo.push_devices WHERE id=p_id FOR UPDATE;
 IF FOUND AND owner<>actor THEN RAISE EXCEPTION 'Dispositivo no disponible' USING ERRCODE='42501'; END IF;
 -- A refreshed token can only have one active account/device subscription.
 DELETE FROM trujillo.push_devices WHERE token=p_token AND id<>p_id;
 INSERT INTO trujillo.push_devices(id,user_id,token,citizen_enabled,operator_enabled,latitude,longitude,radius)
 VALUES(p_id,actor,p_token,p_citizen,p_operator,p_lat,p_lng,p_radius)
 ON CONFLICT(id) DO UPDATE SET token=EXCLUDED.token,citizen_enabled=EXCLUDED.citizen_enabled,
 operator_enabled=EXCLUDED.operator_enabled,latitude=EXCLUDED.latitude,longitude=EXCLUDED.longitude,radius=EXCLUDED.radius,updated_at=now();
 RETURN jsonb_build_object('id',p_id,'citizen_enabled',p_citizen,'operator_enabled',p_operator,'latitude',p_lat,'longitude',p_lng,'radius',p_radius);
END; $$;
CREATE FUNCTION trujillo.push_preferences(p_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; result jsonb;
BEGIN
 actor:=trujillo.current_actor(false);
 SELECT jsonb_build_object('id',id,'citizen_enabled',citizen_enabled,'operator_enabled',operator_enabled,'latitude',latitude,'longitude',longitude,'radius',radius)
 INTO result FROM trujillo.push_devices WHERE id=p_id AND user_id=actor;
 RETURN result;
END; $$;
CREATE FUNCTION trujillo.push_remove(p_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN DELETE FROM trujillo.push_devices WHERE id=p_id AND user_id=trujillo.current_actor(false); END; $$;

CREATE FUNCTION trujillo.push_operator_event(p_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 INSERT INTO trujillo.push_outbox(device_id,user_id,event_key,kind,target_id,expires_at)
 SELECT d.id,d.user_id,'operator:'||p_id::text,'operator',p_id,now()+interval '24 hours'
 FROM trujillo.push_devices d JOIN trujillo.users u ON u.id=d.user_id
 WHERE d.operator_enabled AND u.status='active' AND u.role IN ('operator','admin')
 ON CONFLICT(device_id,event_key) DO NOTHING;
END; $$;
CREATE FUNCTION trujillo.push_new_report() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM trujillo.push_operator_event(NEW.id);
 RETURN NEW;
END; $$;
-- Deferred so the unified transaction has already created the help priority.
CREATE CONSTRAINT TRIGGER push_report AFTER INSERT ON trujillo.reports
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION trujillo.push_new_report();

CREATE FUNCTION trujillo.push_public_incident() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF TG_OP='UPDATE' AND trujillo.is_public_incident(OLD.status,OLD.corroboration_count,OLD.needs_review) THEN RETURN NEW; END IF;
 IF trujillo.is_public_incident(NEW.status,NEW.corroboration_count,NEW.needs_review)
 AND NEW.occurred_at>now()-interval '7 days' AND NEW.occurred_at<=now() THEN
  INSERT INTO trujillo.push_outbox(device_id,user_id,event_key,kind,target_id,expires_at)
  SELECT d.id,d.user_id,'citizen:'||NEW.id::text,'citizen',NEW.id,least(NEW.occurred_at+interval '7 days',now()+interval '6 hours')
  FROM trujillo.push_devices d JOIN trujillo.users u ON u.id=d.user_id
  WHERE d.citizen_enabled AND u.status='active'
  AND extensions.ST_DWithin(NEW.location,extensions.ST_SetSRID(extensions.ST_MakePoint(d.longitude,d.latitude),4326)::extensions.geography,d.radius)
  ON CONFLICT(device_id,event_key) DO NOTHING;
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER push_incident AFTER INSERT OR UPDATE OF status,corroboration_count,needs_review ON trujillo.incidents
 FOR EACH ROW EXECUTE FUNCTION trujillo.push_public_incident();

-- Only the backend DB role can lease/send; no public HTTP route exposes these functions.
CREATE FUNCTION trujillo.push_claim() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE job trujillo.push_outbox; recipient record; incident record; report record; payload jsonb;
BEGIN
 SELECT * INTO job FROM trujillo.push_outbox WHERE NOT done AND next_at<=now()
 AND (leased_until IS NULL OR leased_until<now()) ORDER BY created_at FOR UPDATE SKIP LOCKED LIMIT 1;
 IF NOT FOUND THEN RETURN NULL; END IF;
 SELECT d.*,u.auth_subject,u.role,u.status INTO recipient FROM trujillo.push_devices d JOIN trujillo.users u ON u.id=d.user_id WHERE d.id=job.device_id AND d.user_id=job.user_id;
 IF NOT FOUND OR recipient.status<>'active' OR job.expires_at<=now() OR job.attempts>=8 THEN
  UPDATE trujillo.push_outbox SET done=true WHERE id=job.id; RETURN jsonb_build_object('skipped',true);
 END IF;
 IF job.kind='operator' THEN
  IF NOT recipient.operator_enabled OR recipient.role NOT IN ('operator','admin') THEN
   UPDATE trujillo.push_outbox SET done=true WHERE id=job.id; RETURN jsonb_build_object('skipped',true); END IF;
  SELECT r.category,r.incident_id,h.id AS help_id,coalesce(h.priority,'Sin indicar') AS priority INTO report
  FROM trujillo.reports r LEFT JOIN trujillo.help_requests h ON h.user_id=r.user_id AND h.request_id=r.request_id WHERE r.id=job.target_id AND r.withdrawn_at IS NULL;
  IF NOT FOUND THEN UPDATE trujillo.push_outbox SET done=true WHERE id=job.id; RETURN jsonb_build_object('skipped',true); END IF;
  payload:=jsonb_build_object('kind','operator','target_id',coalesce(report.help_id,report.incident_id)::text,'incident',CASE WHEN report.help_id IS NULL THEN 'true' ELSE 'false' END,
   'title','Nuevo reporte · Urgencia '||report.priority,'body',report.category||'. Abre la app para revisar el caso.');
 ELSE
  SELECT * INTO incident FROM trujillo.incidents WHERE id=job.target_id;
  IF NOT FOUND OR NOT recipient.citizen_enabled OR NOT trujillo.is_public_incident(incident.status,incident.corroboration_count,incident.needs_review)
   OR incident.occurred_at<=now()-interval '7 days' OR incident.occurred_at>now()
   OR NOT extensions.ST_DWithin(incident.location,extensions.ST_SetSRID(extensions.ST_MakePoint(recipient.longitude,recipient.latitude),4326)::extensions.geography,recipient.radius) THEN
   UPDATE trujillo.push_outbox SET done=true WHERE id=job.id; RETURN jsonb_build_object('skipped',true); END IF;
  payload:=jsonb_build_object('kind','citizen','target_id',incident.id::text,'title','Incidente confirmado en tu zona','body',incident.category||'. Toca para consultar el detalle.');
 END IF;
 job.lease:=gen_random_uuid();
 UPDATE trujillo.push_outbox SET lease=job.lease,leased_until=now()+interval '2 minutes',claimed_token=recipient.token,attempts=attempts+1 WHERE id=job.id;
 RETURN payload||jsonb_build_object('job_id',job.id,'lease',job.lease,'token',recipient.token,'account_uid',recipient.auth_subject);
END; $$;
CREATE FUNCTION trujillo.push_finish(p_id uuid,p_lease uuid,p_outcome text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE job trujillo.push_outbox;
BEGIN
 SELECT * INTO job FROM trujillo.push_outbox WHERE id=p_id AND lease=p_lease FOR UPDATE;
 IF NOT FOUND THEN RETURN; END IF;
 IF p_outcome='unregistered' THEN
  DELETE FROM trujillo.push_devices WHERE id=job.device_id AND token=job.claimed_token;
  UPDATE trujillo.push_outbox SET done=true WHERE id=p_id; RETURN;
 END IF;
 UPDATE trujillo.push_outbox SET done=p_outcome IN ('sent','permanent'),leased_until=NULL,
 next_at=now()+make_interval(secs=>least(3600,15*(2^least(attempts,7))::integer)) WHERE id=p_id;
END; $$;
REVOKE ALL ON FUNCTION trujillo.push_register(uuid,text,boolean,boolean,double precision,double precision,integer),trujillo.push_preferences(uuid),trujillo.push_remove(uuid),trujillo.push_operator_event(uuid),trujillo.push_new_report(),trujillo.push_public_incident(),trujillo.push_claim(),trujillo.push_finish(uuid,uuid,text) FROM PUBLIC,anon,authenticated,trujillo_api;
GRANT EXECUTE ON FUNCTION trujillo.push_register(uuid,text,boolean,boolean,double precision,double precision,integer),trujillo.push_preferences(uuid),trujillo.push_remove(uuid),trujillo.push_claim(),trujillo.push_finish(uuid,uuid,text) TO trujillo_api;

CREATE FUNCTION trujillo.push_target(p_kind text,p_id uuid) RETURNS jsonb
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
   'longitude',extensions.ST_X(i.location::extensions.geometry),'occurred_at',i.occurred_at,'status',i.status,'corroboration_count',i.corroboration_count,'needs_review',i.needs_review)
  INTO result FROM trujillo.incidents i WHERE i.id=p_id AND (p_kind='operator_incident' OR
   (trujillo.is_public_incident(i.status,i.corroboration_count,i.needs_review) AND i.occurred_at>now()-interval '7 days' AND i.occurred_at<=now()));
 ELSE RAISE EXCEPTION 'Tipo inválido' USING ERRCODE='22023'; END IF;
 IF result IS NULL THEN RAISE EXCEPTION 'Caso no disponible' USING ERRCODE='P0002'; END IF;
 RETURN result;
END; $$;
REVOKE ALL ON FUNCTION trujillo.push_target(text,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION trujillo.push_target(text,uuid) TO trujillo_api;
