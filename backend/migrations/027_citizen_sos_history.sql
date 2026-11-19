-- Private history is independent of the public map's seven-day visibility.
CREATE INDEX IF NOT EXISTS help_requests_owner_history ON trujillo.help_requests(user_id,received_at DESC,id DESC);
CREATE FUNCTION trujillo.citizen_sos_history(p_limit integer DEFAULT 50,p_offset integer DEFAULT 0) RETURNS SETOF jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid;
BEGIN
 actor:=trujillo.current_actor(false);
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 OR p_offset IS NULL OR p_offset<0 THEN
  RAISE EXCEPTION 'Página inválida' USING ERRCODE='22023'; END IF;
 RETURN QUERY SELECT jsonb_build_object(
  'id',h.id,'category',coalesce(c.category,h.category),'received_at',h.received_at,
  'stage',h.stage,'decision',coalesce(c.decision,CASE WHEN h.stage='Descartada' THEN 'discarded' ELSE 'pending' END),
  'attention',coalesce(c.attention,'none'),'place',coalesce(c.place,h.place),
  'description',coalesce(c.public_description,''),'resolved_at',i.resolved_at)
 FROM trujillo.help_requests h
 LEFT JOIN trujillo.sos_cases c ON c.id=h.id
 LEFT JOIN trujillo.incidents i ON i.id=c.incident_id
 WHERE h.user_id=actor AND h.source='sos'
 ORDER BY h.received_at DESC,h.id DESC LIMIT p_limit OFFSET p_offset;
END; $$;
REVOKE ALL ON FUNCTION trujillo.citizen_sos_history(integer,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION trujillo.citizen_sos_history(integer,integer) TO trujillo_api;
