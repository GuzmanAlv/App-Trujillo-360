-- Private arrival/callback notices, separate from opt-in nearby incident alerts.
ALTER TABLE trujillo.push_devices ADD COLUMN sos_enabled boolean NOT NULL DEFAULT false;
ALTER TABLE trujillo.push_outbox DROP CONSTRAINT push_outbox_kind_check;
ALTER TABLE trujillo.push_outbox ADD CONSTRAINT push_outbox_kind_check CHECK(kind IN ('citizen','operator','sos_arrival','sos_callback'));

CREATE FUNCTION trujillo.push_register_sos(p_id uuid,p_token text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; owner uuid;
BEGIN
 actor:=trujillo.current_actor(false);
 IF p_id IS NULL OR p_token IS NULL OR length(p_token) NOT BETWEEN 20 AND 4096 THEN
  RAISE EXCEPTION 'Registro inválido' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_token,1));
 SELECT user_id INTO owner FROM trujillo.push_devices WHERE id=p_id FOR UPDATE;
 IF FOUND AND owner<>actor THEN RAISE EXCEPTION 'Dispositivo no disponible' USING ERRCODE='42501'; END IF;
 DELETE FROM trujillo.push_devices WHERE token=p_token AND id<>p_id;
 INSERT INTO trujillo.push_devices(id,user_id,token,sos_enabled) VALUES(p_id,actor,p_token,true)
 ON CONFLICT(id) DO UPDATE SET token=EXCLUDED.token,sos_enabled=true,updated_at=now();
END; $$;
REVOKE ALL ON FUNCTION trujillo.push_register_sos(uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION trujillo.push_register_sos(uuid,text) TO trujillo_api;

CREATE FUNCTION trujillo.push_sos_progress() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE citizen uuid;
BEGIN
 IF NEW.attention<>'on_scene' OR OLD.attention='on_scene' THEN RETURN NEW; END IF;
 SELECT user_id INTO citizen FROM trujillo.help_requests WHERE id=NEW.id AND source='sos';
 INSERT INTO trujillo.push_outbox(device_id,user_id,event_key,kind,target_id,expires_at)
 SELECT d.id,d.user_id,'sos-arrival:'||NEW.id::text,'sos_arrival',NEW.id,now()+interval '5 minutes'
 FROM trujillo.push_devices d JOIN trujillo.users u ON u.id=d.user_id
 WHERE d.user_id=citizen AND d.sos_enabled AND u.status='active'
 ON CONFLICT(device_id,event_key) DO NOTHING;
 RETURN NEW;
END; $$;
CREATE TRIGGER push_sos_arrival AFTER UPDATE ON trujillo.sos_cases FOR EACH ROW EXECUTE FUNCTION trujillo.push_sos_progress();

CREATE FUNCTION trujillo.push_sos_callback() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NEW.direction<>'operator' OR NEW.state<>'waiting' THEN RETURN NEW; END IF;
 IF TG_OP='UPDATE' AND OLD.generation=NEW.generation THEN RETURN NEW; END IF;
 INSERT INTO trujillo.push_outbox(device_id,user_id,event_key,kind,target_id,expires_at)
 SELECT d.id,d.user_id,'sos-callback:'||NEW.id::text||':'||NEW.generation::text,'sos_callback',NEW.id,NEW.expires_at
 FROM trujillo.push_devices d JOIN trujillo.users u ON u.id=d.user_id
 WHERE d.user_id=NEW.citizen_id AND d.sos_enabled AND u.status='active'
 ON CONFLICT(device_id,event_key) DO NOTHING;
 RETURN NEW;
END; $$;
CREATE TRIGGER push_sos_callback AFTER INSERT OR UPDATE ON trujillo.call_sessions FOR EACH ROW EXECUTE FUNCTION trujillo.push_sos_callback();

CREATE OR REPLACE FUNCTION trujillo.push_claim() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE job trujillo.push_outbox; recipient record; incident record; report record; payload jsonb;
BEGIN
 SELECT * INTO job FROM trujillo.push_outbox WHERE NOT done AND next_at<=now()
 AND (leased_until IS NULL OR leased_until<now()) ORDER BY created_at FOR UPDATE SKIP LOCKED LIMIT 1;
 IF NOT FOUND THEN RETURN NULL; END IF;
 SELECT d.*,u.auth_subject,u.role,u.status INTO recipient
 FROM trujillo.push_devices d JOIN trujillo.users u ON u.id=d.user_id
 WHERE d.id=job.device_id AND d.user_id=job.user_id;
 IF NOT FOUND OR recipient.status<>'active' OR job.expires_at<=now() OR job.attempts>=8 THEN
  UPDATE trujillo.push_outbox SET done=true WHERE id=job.id;
  RETURN jsonb_build_object('skipped',true);
 END IF;
 IF job.kind IN ('sos_arrival','sos_callback') THEN
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
   WHERE h.id=job.target_id AND h.source='sos';
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

CREATE OR REPLACE FUNCTION trujillo.citizen_sos_cases(p_id uuid DEFAULT NULL) RETURNS SETOF jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid;
BEGIN
 actor:=trujillo.current_actor(false);
 RETURN QUERY SELECT jsonb_build_object('id',h.id,'category',c.category,'latitude',c.latitude,'longitude',c.longitude,
 'arrived_at',(SELECT max(e.created_at) FROM trujillo.sos_case_events e WHERE e.case_id=c.id AND e.payload->>'action'='on_scene'),
 'decision',c.decision,'attention',c.attention,'incident_id',c.incident_id,'description',c.public_description,'place',c.place,
 'received_at',h.received_at,'can_contribute',h.received_at>=now()-interval '7 days')
 FROM trujillo.help_requests h JOIN trujillo.sos_cases c ON c.id=h.id
 WHERE h.user_id=actor AND h.source='sos' AND c.decision='confirmed'
 AND ((p_id IS NULL AND c.attention<>'resolved' AND h.stage NOT IN ('Cerrada','Descartada')) OR h.id=p_id)
 ORDER BY h.received_at DESC LIMIT 200;
END; $$;

