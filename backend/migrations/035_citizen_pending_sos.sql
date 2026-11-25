-- Citizen-only map: pending requests stay private and never create incidents.
CREATE FUNCTION trujillo.citizen_sos_map_cases(p_id uuid DEFAULT NULL) RETURNS SETOF jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid;
BEGIN
 actor:=trujillo.current_actor(false);
 RETURN QUERY SELECT * FROM trujillo.citizen_sos_cases(p_id);
 RETURN QUERY SELECT jsonb_build_object(
  'id',h.id,'category',coalesce(c.category,h.category),'latitude',h.latitude,'longitude',h.longitude,
  'received_at',h.received_at,'decision','pending','attention','none','incident_id',NULL,
  'description','','place','','arrived_at',NULL,'can_contribute',false,'assignment_state','pending',
  'call_state',(SELECT CASE WHEN s.expires_at<=now() AND s.state='waiting' THEN 'unanswered' ELSE s.state END
   FROM trujillo.call_sessions s WHERE s.id=h.id),
  'escalation_level',coalesce((SELECT e.level FROM trujillo.sos_escalation e WHERE e.case_id=h.id),0))
 FROM trujillo.help_requests h LEFT JOIN trujillo.sos_cases c ON c.id=h.id
 WHERE h.user_id=actor AND h.source='sos' AND h.stage NOT IN ('Cerrada','Descartada')
 AND coalesce(c.decision,'pending')='pending' AND (p_id IS NULL OR h.id=p_id)
 ORDER BY h.received_at DESC,h.id;
END; $$;
REVOKE ALL ON FUNCTION trujillo.citizen_sos_map_cases(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION trujillo.citizen_sos_map_cases(uuid) TO trujillo_api;
