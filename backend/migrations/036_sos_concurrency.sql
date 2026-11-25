-- Read-only polling does not take the global assignment lock or renew every case.
CREATE INDEX help_open_sos_idx ON trujillo.help_requests(received_at DESC,id)
 WHERE source='sos' AND stage NOT IN ('Cerrada','Descartada');

-- Verified identity still synchronizes on every request, but unchanged accounts
-- no longer acquire a write lock just to poll their calls or map.
CREATE OR REPLACE FUNCTION trujillo.sync_identity_email(p_email text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 UPDATE trujillo.users u SET auth_email=lower(p_email),
 role=CASE WHEN u.role='citizen' AND EXISTS(SELECT 1 FROM trujillo.operator_invitations v WHERE v.email=lower(p_email) AND v.active) THEN 'operator' ELSE u.role END
 WHERE u.auth_provider='firebase' AND u.auth_subject=current_setting('app.firebase_uid',true) AND u.status='active'
 AND (u.auth_email IS DISTINCT FROM lower(p_email) OR
 (u.role='citizen' AND EXISTS(SELECT 1 FROM trujillo.operator_invitations v WHERE v.email=lower(p_email) AND v.active)));
END; $$;

CREATE FUNCTION trujillo.read_call_status(p_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; is_op boolean; h trujillo.help_requests; c trujillo.sos_cases;
 s trujillo.call_sessions; effective text;
BEGIN
 actor:=trujillo.current_actor(false);
 SELECT role IN ('operator','admin') INTO is_op FROM trujillo.users WHERE id=actor;
 SELECT * INTO h FROM trujillo.help_requests WHERE id=p_id AND source='sos';
 IF h.id IS NULL OR (h.user_id<>actor AND NOT is_op) THEN RAISE EXCEPTION 'No disponible' USING ERRCODE='42501'; END IF;
 SELECT * INTO c FROM trujillo.sos_cases WHERE id=p_id;
 SELECT * INTO s FROM trujillo.call_sessions WHERE id=p_id;
 IF c.decision='confirmed' AND h.user_id<>actor AND c.operator_id IS DISTINCT FROM actor THEN
  RAISE EXCEPTION 'Caso reasignado' USING ERRCODE='42501'; END IF;
 IF actor=h.user_id AND c.decision='confirmed' AND EXISTS(SELECT 1 FROM trujillo.sos_dispatch WHERE case_id=p_id AND state<>'assigned') THEN
  RETURN jsonb_build_object('id',p_id,'state',CASE WHEN EXISTS(SELECT 1 FROM trujillo.sos_contact_requests WHERE case_id=p_id AND expires_at>now()) THEN 'waiting_assignment' ELSE 'unanswered' END,'can_join',false);
 END IF;
 IF s.id IS NULL THEN RAISE EXCEPTION 'Sin llamada' USING ERRCODE='P0002'; END IF;
 effective:=CASE WHEN s.expires_at<=now() AND s.state='waiting' THEN 'unanswered'
  WHEN s.expires_at<=now() AND s.state='accepted' THEN 'ended' ELSE s.state END;
 RETURN jsonb_build_object('id',s.id,'state',effective,'expires_at',s.expires_at,
  'can_join',effective='accepted' AND (actor=s.citizen_id OR actor=s.operator_id),
  'room','sos-'||s.id::text||'-'||s.generation::text,'participant',actor::text,'generation',s.generation);
END; $$;

ALTER FUNCTION trujillo.call_action(uuid,text) RENAME TO call_action_v35;
CREATE FUNCTION trujillo.call_action(p_id uuid,p_action text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb;
BEGIN
 IF p_action='status' THEN RETURN trujillo.read_call_status(p_id); END IF;
 IF p_action='callback' THEN
  IF EXISTS(SELECT 1 FROM trujillo.sos_cases WHERE id=p_id AND decision='confirmed'
   AND operator_id IS DISTINCT FROM trujillo.current_actor(true)) THEN
   RAISE EXCEPTION 'Caso asignado a otro operador' USING ERRCODE='42501'; END IF;
  result:=trujillo.take_sos_call(p_id,NULL);
  IF result ? 'error_code' THEN RETURN result; END IF;
 END IF;
 RETURN trujillo.call_action_v35(p_id,p_action);
END; $$;

CREATE FUNCTION trujillo.take_sos_call(p_id uuid,p_generation uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; h trujillo.help_requests; c trujillo.sos_cases; s trujillo.call_sessions;
 previous record; result jsonb; call_data jsonb; offer boolean;
BEGIN
 actor:=trujillo.current_actor(true);
 PERFORM pg_advisory_xact_lock(360017);
 PERFORM trujillo.expire_sos_claims();
 SELECT * INTO h FROM trujillo.help_requests WHERE id=p_id AND source='sos';
 IF h.id IS NULL OR h.user_id=actor THEN RAISE EXCEPTION 'No disponible' USING ERRCODE='42501'; END IF;
 IF h.stage IN ('Cerrada','Descartada') THEN RETURN jsonb_build_object('error_code','SOS_TAKEN'); END IF;
 SELECT * INTO c FROM trujillo.sos_cases WHERE id=p_id;
 SELECT * INTO s FROM trujillo.call_sessions WHERE id=p_id;
 offer:=EXISTS(SELECT 1 FROM trujillo.sos_dispatch WHERE case_id=p_id AND state='offered' AND offer_expires_at>now());
 IF coalesce(c.operator_id,s.operator_id,actor)<>actor THEN RETURN jsonb_build_object('error_code','SOS_TAKEN'); END IF;
 IF NOT offer AND p_generation IS NOT NULL AND p_generation IS DISTINCT FROM s.generation THEN
  RETURN jsonb_build_object('error_code','SOS_CALL_CHANGED'); END IF;
 IF EXISTS(SELECT 1 FROM trujillo.call_sessions WHERE id<>p_id AND state IN ('waiting','accepted') AND expires_at>now()
  AND (operator_id=actor OR citizen_id=actor))
  OR EXISTS(SELECT 1 FROM trujillo.sos_cases WHERE id<>p_id AND operator_id=actor AND decision='confirmed' AND attention IN ('en_route','on_scene')) THEN
  RETURN jsonb_build_object('error_code','SOS_BUSY'); END IF;
 -- The nested transaction restores earlier reservations if accepting the selected SOS fails.
 BEGIN
  FOR previous IN SELECT id FROM trujillo.sos_cases WHERE id<>p_id AND operator_id=actor AND decision='pending' LOOP
   PERFORM trujillo.release_sos_claim(previous.id);
  END LOOP;
  result:=trujillo.claim_sos(p_id);
  SELECT * INTO s FROM trujillo.call_sessions WHERE id=p_id;
  IF s.id IS NULL THEN
   INSERT INTO trujillo.call_sessions(id,citizen_id,state,ended_at,expires_at)
   VALUES(p_id,h.user_id,'ended',now(),now());
  END IF;
  IF s.state='waiting' AND s.direction='citizen' AND s.expires_at>now() THEN
   call_data:=trujillo.call_action(p_id,'accept');
  ELSE
   call_data:=trujillo.read_call_status(p_id);
  END IF;
  RETURN jsonb_build_object('case',result,'call',call_data-'participant','call_accepted',call_data->>'state'='accepted');
 EXCEPTION WHEN raise_exception OR no_data_found THEN
  RETURN jsonb_build_object('error_code','SOS_TAKEN');
 END;
END; $$;

CREATE FUNCTION trujillo.call_heartbeat(p_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid;
BEGIN
 actor:=trujillo.current_actor(true);
 PERFORM pg_advisory_xact_lock(360017);
 IF NOT EXISTS(SELECT 1 FROM trujillo.call_sessions WHERE id=p_id AND operator_id=actor AND state='accepted' AND expires_at>now()) THEN
  RAISE EXCEPTION 'Llamada no asignada' USING ERRCODE='42501'; END IF;
 PERFORM trujillo.operator_heartbeat(true);
 RETURN jsonb_build_object('owned',trujillo.renew_sos_claim(p_id));
END; $$;

CREATE FUNCTION trujillo.end_call_generation(p_id uuid,p_generation uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE current_call jsonb; requested_room text; actor uuid;
BEGIN
 actor:=trujillo.current_actor(false);
 PERFORM pg_advisory_xact_lock(360017);
 IF NOT EXISTS(SELECT 1 FROM trujillo.help_requests h LEFT JOIN trujillo.call_sessions s ON s.id=h.id
  WHERE h.id=p_id AND (h.user_id=actor OR s.operator_id=actor)) THEN
  RAISE EXCEPTION 'Llamada no asignada' USING ERRCODE='42501'; END IF;
 current_call:=trujillo.read_call_status(p_id);
 IF p_generation IS NOT NULL THEN
  requested_room:='sos-'||p_id::text||'-'||p_generation::text;
  IF current_call->>'room' IS DISTINCT FROM requested_room THEN
   RETURN jsonb_build_object('id',p_id,'state','ended','room',requested_room,'stale',true);
  END IF;
 END IF;
 RETURN trujillo.call_action(p_id,'end');
END; $$;

CREATE OR REPLACE FUNCTION trujillo.sos_map_call_status(p_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c trujillo.call_sessions;
BEGIN
 PERFORM trujillo.current_actor(true);
 SELECT * INTO c FROM trujillo.call_sessions WHERE id=p_id;
 RETURN jsonb_build_object('call_generation',c.generation,
  'call_state',CASE WHEN c.state='waiting' AND c.expires_at<=now() THEN 'unanswered'
   WHEN c.state='accepted' AND c.expires_at<=now() THEN 'ended' ELSE c.state END,
  'call_waiting',coalesce(c.direction='citizen' AND c.state='waiting' AND c.expires_at>now(),false),
  'unanswered_alert',coalesce(c.direction='citizen' AND c.accepted_at IS NULL
   AND least(coalesce(c.ended_at,now()),c.expires_at)-c.created_at>=interval '10 seconds',false));
END; $$;

CREATE OR REPLACE FUNCTION trujillo.operator_sos_map_data() RETURNS SETOF jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid;
BEGIN
 actor:=trujillo.current_actor(true);
 RETURN QUERY SELECT jsonb_build_object('id',h.id,'received_at',h.received_at,
 'latitude',coalesce(p.latitude,c.latitude,h.latitude),'longitude',coalesce(p.longitude,c.longitude,h.longitude),
 'decision',coalesce(c.decision,'pending'),'attention',CASE WHEN d.state IN ('searching','offered') THEN 'none' ELSE coalesce(c.attention,'none') END,
 'category',coalesce(c.category,h.category),'support_requested',coalesce(c.support_requested,false),'incident_id',c.incident_id,
 'can_track',coalesce(c.operator_id=actor AND coalesce(s.operator_id,c.operator_id)=actor AND coalesce(d.state,'assigned')='assigned',false),
 'available',coalesce(c.operator_id,s.operator_id) IS NULL AND coalesce(c.decision,'pending')='pending',
 'claimed_by_me',coalesce(c.operator_id,s.operator_id)=actor AND coalesce(c.decision,'pending')='pending',
 'alert_in_range',trujillo.operator_in_sos_zone(actor,h.id),
 'assignment_state',coalesce(d.state,CASE WHEN c.operator_id IS NULL THEN 'searching' ELSE 'assigned' END),
 'assignment_offer',coalesce(d.state='offered' AND c.operator_id=actor AND d.offer_expires_at>now(),false),
 'offer_expires_at',d.offer_expires_at,'operator_name',CASE WHEN d.state='assigned' THEN u.display_name ELSE NULL END,
 'escalation_level',coalesce(e.level,0))||trujillo.sos_map_call_status(h.id)
 FROM trujillo.help_requests h LEFT JOIN trujillo.sos_cases c ON c.id=h.id
 LEFT JOIN trujillo.call_sessions s ON s.id=h.id LEFT JOIN trujillo.sos_dispatch d ON d.case_id=h.id
 LEFT JOIN trujillo.users u ON u.id=c.operator_id LEFT JOIN trujillo.sos_escalation e ON e.case_id=h.id
 LEFT JOIN trujillo.sos_live_positions p ON p.case_id=h.id AND c.operator_id=actor AND c.decision='confirmed'
 WHERE h.source='sos' AND h.stage NOT IN ('Cerrada','Descartada')
 AND coalesce(c.decision,'pending')<>'discarded' AND coalesce(c.attention,'none')<>'resolved'
 ORDER BY h.received_at DESC,h.id;
END; $$;

CREATE FUNCTION trujillo.operator_help_cases() RETURNS SETOF jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM trujillo.current_actor(true);
 RETURN QUERY SELECT (to_jsonb(h)-'user_id'-'submitted_priority')||m||jsonb_build_object(
 'sos_case',jsonb_build_object('decision',m->>'decision','attention',m->>'attention','support_requested',m->'support_requested'),
 'events','[]'::jsonb)
 FROM trujillo.operator_sos_map_data() m JOIN trujillo.help_requests h ON h.id=(m->>'id')::uuid;
 RETURN QUERY SELECT r FROM trujillo.list_help_v30(true) r
 WHERE r->>'source'<>'sos' OR r->>'stage' IN ('Cerrada','Descartada');
END; $$;

REVOKE ALL ON FUNCTION trujillo.call_action_v35(uuid,text) FROM PUBLIC,anon,authenticated,trujillo_api;
REVOKE ALL ON FUNCTION trujillo.read_call_status(uuid),trujillo.call_action(uuid,text),trujillo.take_sos_call(uuid,uuid),
 trujillo.call_heartbeat(uuid),trujillo.operator_help_cases(),trujillo.end_call_generation(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION trujillo.read_call_status(uuid),trujillo.call_action(uuid,text),trujillo.take_sos_call(uuid,uuid),
 trujillo.call_heartbeat(uuid),trujillo.operator_help_cases(),trujillo.end_call_generation(uuid,uuid) TO trujillo_api;
