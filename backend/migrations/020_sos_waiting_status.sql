-- Minimal operator-only call state for map markers; no caller identity or notes.
CREATE FUNCTION trujillo.sos_map_call_status(p_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c trujillo.call_sessions;
BEGIN
 PERFORM trujillo.current_actor(true);
 SELECT * INTO c FROM trujillo.call_sessions WHERE id=p_id;
 RETURN jsonb_build_object(
  'call_state',CASE WHEN c.state='waiting' AND c.expires_at<=now() THEN 'unanswered'
    WHEN c.state='accepted' AND c.expires_at<=now() THEN 'ended' ELSE c.state END,
  'call_waiting',coalesce(c.direction='citizen' AND c.state='waiting' AND c.expires_at>now(),false),
  'unanswered_alert',coalesce(c.direction='citizen' AND c.accepted_at IS NULL
   AND least(coalesce(c.ended_at,now()),c.expires_at)-c.created_at>=interval '10 seconds',false));
END; $$;
REVOKE ALL ON FUNCTION trujillo.sos_map_call_status(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION trujillo.sos_map_call_status(uuid) TO trujillo_api;
