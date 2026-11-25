-- Operator presence controls alarms, never visibility or permission to help.
CREATE TABLE trujillo.operator_presence (
 user_id uuid PRIMARY KEY REFERENCES trujillo.users(id) ON DELETE CASCADE,
 latitude double precision NOT NULL, longitude double precision NOT NULL,
 accuracy double precision NOT NULL, observed_at timestamptz NOT NULL
);
ALTER TABLE trujillo.operator_presence ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON trujillo.operator_presence FROM PUBLIC,anon,authenticated,trujillo_api;

CREATE FUNCTION trujillo.operator_position(p_lat double precision,p_lng double precision,p_accuracy double precision,p_observed timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid;
BEGIN
 actor:=trujillo.current_actor(true);
 IF p_lat IS NULL OR p_lng IS NULL OR p_accuracy IS NULL OR p_observed IS NULL OR
 NOT (p_lat BETWEEN -90 AND 90 AND p_lng BETWEEN -180 AND 180 AND p_accuracy BETWEEN 0 AND 100)
 OR p_observed<clock_timestamp()-interval '30 seconds' OR p_observed>clock_timestamp()+interval '5 seconds'
 THEN RAISE EXCEPTION 'GPS inválido' USING ERRCODE='22023'; END IF;
 INSERT INTO trujillo.operator_presence VALUES(actor,p_lat,p_lng,p_accuracy,p_observed)
 ON CONFLICT(user_id) DO UPDATE SET latitude=p_lat,longitude=p_lng,accuracy=p_accuracy,observed_at=p_observed
 WHERE operator_presence.observed_at<EXCLUDED.observed_at;
 RETURN jsonb_build_object('status','saved','radius_meters',15000);
END; $$;

CREATE FUNCTION trujillo.clear_operator_position() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid;
BEGIN
 actor:=trujillo.current_actor(true);
 DELETE FROM trujillo.operator_presence WHERE user_id=actor;
END;
$$;

-- Internal helper. The API cannot query another operator's position or zone.
CREATE FUNCTION trujillo.operator_in_sos_zone(p_actor uuid,p_case uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM trujillo.operator_presence p JOIN trujillo.help_requests h ON h.id=p_case
 WHERE p.user_id=p_actor AND h.source='sos' AND p.observed_at>now()-interval '10 minutes'
 AND extensions.ST_DWithin(
  extensions.ST_SetSRID(extensions.ST_MakePoint(p.longitude,p.latitude),4326)::extensions.geography,
  extensions.ST_SetSRID(extensions.ST_MakePoint(h.longitude,h.latitude),4326)::extensions.geography,15000));
$$;

-- Keep alarm decisions consistent when an operator opens a distant case.
ALTER FUNCTION trujillo.sos_case_read(uuid) RENAME TO sos_case_read_v32;
CREATE FUNCTION trujillo.sos_case_read(p_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb; actor uuid;
BEGIN
 result:=trujillo.sos_case_read_v32(p_id);
 actor:=trujillo.current_actor(true);
 RETURN result||jsonb_build_object('alert_in_range',trujillo.operator_in_sos_zone(actor,p_id));
END; $$;
REVOKE ALL ON FUNCTION trujillo.sos_case_read_v32(uuid) FROM PUBLIC,anon,authenticated,trujillo_api;
REVOKE ALL ON FUNCTION trujillo.sos_case_read(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION trujillo.sos_case_read(uuid) TO trujillo_api;

CREATE FUNCTION trujillo.operator_sos_map_data() RETURNS SETOF jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid;
BEGIN
 actor:=trujillo.current_actor(true);
 PERFORM trujillo.expire_sos_claims();
 UPDATE trujillo.sos_cases SET claim_expires_at=now()+interval '2 minutes'
 WHERE operator_id=actor AND decision='pending';
 RETURN QUERY SELECT jsonb_build_object('id',h.id,'received_at',h.received_at,
 'latitude',coalesce(p.latitude,c.latitude,h.latitude),'longitude',coalesce(p.longitude,c.longitude,h.longitude),
 'decision',coalesce(c.decision,'pending'),'attention',coalesce(c.attention,'none'),
 'category',coalesce(c.category,h.category),'support_requested',coalesce(c.support_requested,false),'incident_id',c.incident_id,
 'can_track',coalesce(c.operator_id=actor AND coalesce(s.operator_id,c.operator_id)=actor,false),
 'available',coalesce(c.operator_id,s.operator_id) IS NULL AND coalesce(c.decision,'pending')='pending',
 'claimed_by_me',coalesce(c.operator_id,s.operator_id)=actor AND coalesce(c.decision,'pending')='pending',
 'alert_in_range',trujillo.operator_in_sos_zone(actor,h.id))||trujillo.sos_map_call_status(h.id)
 FROM trujillo.help_requests h LEFT JOIN trujillo.sos_cases c ON c.id=h.id
 LEFT JOIN trujillo.call_sessions s ON s.id=h.id
 LEFT JOIN trujillo.sos_live_positions p ON p.case_id=h.id AND c.operator_id=actor AND c.decision='confirmed'
 WHERE h.source='sos' AND h.stage NOT IN ('Cerrada','Descartada')
 AND coalesce(c.decision,'pending')<>'discarded' AND coalesce(c.attention,'none')<>'resolved'
 ORDER BY h.received_at DESC,h.id;
END; $$;

CREATE OR REPLACE FUNCTION trujillo.push_operator_event(p_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE is_sos boolean;
BEGIN
 is_sos:=EXISTS(SELECT 1 FROM trujillo.help_requests WHERE id=p_id AND source='sos');
 INSERT INTO trujillo.push_outbox(device_id,user_id,event_key,kind,target_id,expires_at)
 SELECT d.id,d.user_id,'operator:'||p_id::text,'operator',p_id,now()+interval '24 hours'
 FROM trujillo.push_devices d JOIN trujillo.users u ON u.id=d.user_id
 WHERE d.operator_enabled AND u.status='active' AND u.role IN ('operator','admin')
 AND (NOT is_sos OR trujillo.operator_in_sos_zone(d.user_id,p_id))
 ON CONFLICT(device_id,event_key) DO NOTHING;
END; $$;

ALTER FUNCTION trujillo.push_claim() RENAME TO push_claim_v32;
CREATE FUNCTION trujillo.push_claim() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb; job trujillo.push_outbox;
BEGIN
 result:=trujillo.push_claim_v32();
 IF result IS NULL OR result->>'skipped'='true' OR result->>'assigned_call'='true' OR result->>'kind'<>'operator' THEN RETURN result; END IF;
 SELECT * INTO job FROM trujillo.push_outbox WHERE id=(result->>'job_id')::uuid;
 IF EXISTS(SELECT 1 FROM trujillo.help_requests WHERE id=job.target_id AND source='sos')
 AND NOT trujillo.operator_in_sos_zone(job.user_id,job.target_id) THEN
  UPDATE trujillo.push_outbox SET done=true WHERE id=job.id;
  RETURN jsonb_build_object('skipped',true);
 END IF;
 RETURN result;
END; $$;
REVOKE ALL ON FUNCTION trujillo.operator_in_sos_zone(uuid,uuid),trujillo.push_claim_v32() FROM PUBLIC,anon,authenticated,trujillo_api;
REVOKE ALL ON FUNCTION trujillo.operator_position(double precision,double precision,double precision,timestamptz),
 trujillo.clear_operator_position(),trujillo.operator_sos_map_data(),trujillo.push_claim() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION trujillo.operator_position(double precision,double precision,double precision,timestamptz),
 trujillo.clear_operator_position(),trujillo.operator_sos_map_data(),trujillo.push_claim() TO trujillo_api;
