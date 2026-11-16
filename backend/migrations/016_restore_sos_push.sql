-- Restore SOS dispatch after the moving-location migration replaced push_claim.
INSERT INTO trujillo.push_migrations(version) VALUES (3);

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
 IF job.kind='operator' THEN
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
 job.lease:=gen_random_uuid();
 UPDATE trujillo.push_outbox SET lease=job.lease,leased_until=now()+interval '2 minutes',
  claimed_token=recipient.token,attempts=attempts+1 WHERE id=job.id;
 RETURN payload||jsonb_build_object('job_id',job.id,'lease',job.lease,
  'token',recipient.token,'account_uid',recipient.auth_subject);
END; $$;
