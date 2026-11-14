-- Private SOS requests never create a public incident.
CREATE TABLE trujillo.sos_migrations(version integer PRIMARY KEY);
INSERT INTO trujillo.sos_migrations VALUES(1);
ALTER TABLE trujillo.sos_migrations ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON trujillo.sos_migrations TO trujillo_api;
CREATE POLICY sos_version_read ON trujillo.sos_migrations FOR SELECT TO trujillo_api USING(true);
ALTER TABLE trujillo.help_requests ADD COLUMN source text NOT NULL DEFAULT 'report'
 CHECK(source IN ('report','sos'));

CREATE FUNCTION trujillo.submit_sos(p_request uuid,p_lat double precision,p_lng double precision) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; old trujillo.help_requests; result trujillo.help_requests;
BEGIN
 actor:=trujillo.current_actor(false);
 IF p_request IS NULL OR p_lat IS NULL OR NOT(p_lat BETWEEN -90 AND 90)
 OR p_lng IS NULL OR NOT(p_lng BETWEEN -180 AND 180) THEN
  RAISE EXCEPTION 'Datos inválidos' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||p_request::text,0));
 SELECT * INTO old FROM trujillo.help_requests WHERE user_id=actor AND request_id=p_request;
 IF FOUND THEN
  IF old.source<>'sos' OR (old.latitude,old.longitude) IS DISTINCT FROM (p_lat,p_lng) THEN
   RAISE EXCEPTION 'Solicitud reutilizada con otros datos' USING ERRCODE='P0001'; END IF;
  RETURN to_jsonb(old)-'user_id';
 END IF;
 INSERT INTO trujillo.help_requests(user_id,request_id,category,place,description,latitude,longitude,submitted_priority,priority,source)
 VALUES(actor,p_request,'Auxilio','Ubicación SOS','',p_lat,p_lng,'Alta','Alta','sos') RETURNING * INTO result;
 INSERT INTO trujillo.help_events(request_id,actor_id,stage,priority,reason)
 VALUES(result.id,actor,'Recibida','Alta','SOS recibido por la plataforma. No confirma atención ni envío de personal.');
 PERFORM trujillo.push_operator_event(result.id);
 RETURN to_jsonb(result)-'user_id';
END; $$;
REVOKE ALL ON FUNCTION trujillo.submit_sos(uuid,double precision,double precision) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION trujillo.submit_sos(uuid,double precision,double precision) TO trujillo_api;

CREATE OR REPLACE FUNCTION trujillo.push_claim() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE job trujillo.push_outbox; recipient record; incident record; report record; payload jsonb;
BEGIN
 SELECT * INTO job FROM trujillo.push_outbox WHERE NOT done AND next_at<=now()
 AND (leased_until IS NULL OR leased_until<now()) ORDER BY created_at FOR UPDATE SKIP LOCKED LIMIT 1;
 IF NOT FOUND THEN RETURN NULL; END IF;
 SELECT d.*,u.auth_subject,u.role,u.status INTO recipient FROM trujillo.push_devices d JOIN trujillo.users u ON u.id=d.user_id WHERE d.id=job.device_id AND d.user_id=job.user_id;
 IF NOT FOUND OR recipient.status<>'active' OR job.expires_at<=now() OR job.attempts>=8 THEN
  UPDATE trujillo.push_outbox SET done=true WHERE id=job.id; RETURN jsonb_build_object('skipped',true); END IF;
 IF job.kind='operator' THEN
  IF NOT recipient.operator_enabled OR recipient.role NOT IN ('operator','admin') THEN
   UPDATE trujillo.push_outbox SET done=true WHERE id=job.id; RETURN jsonb_build_object('skipped',true); END IF;
  SELECT r.category,r.incident_id,h.id AS help_id,coalesce(h.priority,'Sin indicar') AS priority INTO report
  FROM trujillo.reports r LEFT JOIN trujillo.help_requests h ON h.user_id=r.user_id AND h.request_id=r.request_id WHERE r.id=job.target_id AND r.withdrawn_at IS NULL;
  IF FOUND THEN
   payload:=jsonb_build_object('kind','operator','target_id',coalesce(report.help_id,report.incident_id)::text,'incident',CASE WHEN report.help_id IS NULL THEN 'true' ELSE 'false' END,
    'title','Nuevo reporte','body',report.category||'. Abre la app para revisar el caso.');
  ELSE
   SELECT h.id AS help_id INTO report FROM trujillo.help_requests h WHERE h.id=job.target_id AND h.source='sos';
   IF NOT FOUND THEN UPDATE trujillo.push_outbox SET done=true WHERE id=job.id; RETURN jsonb_build_object('skipped',true); END IF;
   payload:=jsonb_build_object('kind','operator','target_id',report.help_id::text,'incident','false',
    'title','SOS · Solicitud de ayuda','body','Una persona compartió su ubicación. Toca para revisar la solicitud.');
  END IF;
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
