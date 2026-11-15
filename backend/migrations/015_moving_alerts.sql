-- Moving alerts require recent device coordinates. Older app versions keep their fixed zones.
ALTER TABLE trujillo.push_devices
 ADD COLUMN moving_enabled boolean NOT NULL DEFAULT false,
 ADD COLUMN location_updated_at timestamptz;
ALTER TABLE trujillo.push_devices ADD CONSTRAINT moving_requires_citizen
 CHECK (NOT moving_enabled OR citizen_enabled);
INSERT INTO trujillo.push_migrations(version) VALUES (2);

CREATE FUNCTION trujillo.push_register(p_id uuid,p_token text,p_citizen boolean,p_operator boolean,p_lat double precision,p_lng double precision,p_radius integer,p_moving boolean) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; owner uuid;
BEGIN
 actor:=trujillo.current_actor(p_operator);
 IF p_id IS NULL OR p_token IS NULL OR length(p_token) NOT BETWEEN 20 AND 4096
 OR p_citizen IS NULL OR p_operator IS NULL OR p_moving IS NULL OR p_radius IS NULL OR p_radius NOT BETWEEN 100 AND 3000
 OR (p_lat IS NOT NULL AND NOT(p_lat BETWEEN -90 AND 90)) OR (p_lng IS NOT NULL AND NOT(p_lng BETWEEN -180 AND 180))
 OR (p_citizen AND (p_lat IS NULL OR p_lng IS NULL)) OR (p_moving AND NOT p_citizen)
 THEN RAISE EXCEPTION 'Datos inválidos' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_token,1));
 SELECT user_id INTO owner FROM trujillo.push_devices WHERE id=p_id FOR UPDATE;
 IF FOUND AND owner<>actor THEN RAISE EXCEPTION 'Dispositivo no disponible' USING ERRCODE='42501'; END IF;
 DELETE FROM trujillo.push_devices WHERE token=p_token AND id<>p_id;
 INSERT INTO trujillo.push_devices(id,user_id,token,citizen_enabled,operator_enabled,latitude,longitude,radius,moving_enabled,location_updated_at)
 VALUES(p_id,actor,p_token,p_citizen,p_operator,p_lat,p_lng,p_radius,p_moving,CASE WHEN p_moving THEN now() ELSE NULL END)
 ON CONFLICT(id) DO UPDATE SET token=EXCLUDED.token,citizen_enabled=EXCLUDED.citizen_enabled,
 operator_enabled=EXCLUDED.operator_enabled,latitude=EXCLUDED.latitude,longitude=EXCLUDED.longitude,radius=EXCLUDED.radius,
 moving_enabled=EXCLUDED.moving_enabled,
 location_updated_at=CASE WHEN NOT EXCLUDED.moving_enabled THEN NULL
  WHEN NOT trujillo.push_devices.moving_enabled THEN now()
  ELSE trujillo.push_devices.location_updated_at END,updated_at=now();
 RETURN trujillo.push_preferences(p_id);
END; $$;
REVOKE ALL ON FUNCTION trujillo.push_register(uuid,text,boolean,boolean,double precision,double precision,integer,boolean) FROM PUBLIC,anon,authenticated,trujillo_api;
GRANT EXECUTE ON FUNCTION trujillo.push_register(uuid,text,boolean,boolean,double precision,double precision,integer,boolean) TO trujillo_api;

CREATE OR REPLACE FUNCTION trujillo.push_preferences(p_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; result jsonb;
BEGIN
 actor:=trujillo.current_actor(false);
 SELECT jsonb_build_object('id',id,'citizen_enabled',citizen_enabled,'operator_enabled',operator_enabled,
  'moving_enabled',moving_enabled,'latitude',latitude,'longitude',longitude,'radius',radius,
  'location_updated_at',location_updated_at)
 INTO result FROM trujillo.push_devices WHERE id=p_id AND user_id=actor;
 RETURN result;
END; $$;

CREATE FUNCTION trujillo.push_update_location(p_id uuid,p_lat double precision,p_lng double precision) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF p_lat IS NULL OR p_lng IS NULL OR NOT(p_lat BETWEEN -90 AND 90) OR NOT(p_lng BETWEEN -180 AND 180)
 THEN RAISE EXCEPTION 'Ubicación inválida' USING ERRCODE='22023'; END IF;
 UPDATE trujillo.push_devices SET latitude=p_lat,longitude=p_lng,location_updated_at=now(),updated_at=now()
 WHERE id=p_id AND user_id=trujillo.current_actor(false) AND citizen_enabled AND moving_enabled;
 IF NOT FOUND THEN RAISE EXCEPTION 'Avisos de ubicación no activos' USING ERRCODE='P0002'; END IF;
END; $$;
REVOKE ALL ON FUNCTION trujillo.push_update_location(uuid,double precision,double precision) FROM PUBLIC,anon,authenticated,trujillo_api;
GRANT EXECUTE ON FUNCTION trujillo.push_update_location(uuid,double precision,double precision) TO trujillo_api;

CREATE OR REPLACE FUNCTION trujillo.push_public_incident() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF TG_OP='UPDATE' AND trujillo.is_public_incident(OLD.status,OLD.corroboration_count,OLD.needs_review) THEN RETURN NEW; END IF;
 IF trujillo.is_public_incident(NEW.status,NEW.corroboration_count,NEW.needs_review)
 AND NEW.occurred_at>now()-interval '7 days' AND NEW.occurred_at<=now() THEN
  INSERT INTO trujillo.push_outbox(device_id,user_id,event_key,kind,target_id,expires_at)
  SELECT d.id,d.user_id,'citizen:'||NEW.id::text,'citizen',NEW.id,least(NEW.occurred_at+interval '7 days',now()+interval '6 hours')
  FROM trujillo.push_devices d JOIN trujillo.users u ON u.id=d.user_id
  WHERE d.citizen_enabled AND u.status='active'
  AND (NOT d.moving_enabled OR d.location_updated_at>now()-interval '20 minutes')
  AND extensions.ST_DWithin(NEW.location,extensions.ST_SetSRID(extensions.ST_MakePoint(d.longitude,d.latitude),4326)::extensions.geography,d.radius)
  ON CONFLICT(device_id,event_key) DO NOTHING;
 END IF;
 RETURN NEW;
END; $$;

CREATE OR REPLACE FUNCTION trujillo.push_claim() RETURNS jsonb
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
   OR (recipient.moving_enabled AND (recipient.location_updated_at IS NULL OR recipient.location_updated_at<=now()-interval '20 minutes'))
   OR NOT extensions.ST_DWithin(incident.location,extensions.ST_SetSRID(extensions.ST_MakePoint(recipient.longitude,recipient.latitude),4326)::extensions.geography,recipient.radius) THEN
   UPDATE trujillo.push_outbox SET done=true WHERE id=job.id; RETURN jsonb_build_object('skipped',true); END IF;
  payload:=jsonb_build_object('kind','citizen','target_id',incident.id::text,'moving',recipient.moving_enabled,
   'title','Incidente confirmado cerca de ti','body',incident.category||'. Toca para consultar el detalle.');
 END IF;
 job.lease:=gen_random_uuid();
 UPDATE trujillo.push_outbox SET lease=job.lease,leased_until=now()+interval '2 minutes',claimed_token=recipient.token,attempts=attempts+1 WHERE id=job.id;
 RETURN payload||jsonb_build_object('job_id',job.id,'lease',job.lease,'token',recipient.token,'account_uid',recipient.auth_subject);
END; $$;
