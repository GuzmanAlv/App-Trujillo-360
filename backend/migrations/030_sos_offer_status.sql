-- Private claim state for the operator map. The API role cannot read case tables.
CREATE FUNCTION trujillo.sos_offer_status(p_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; owner uuid; decision text;
BEGIN
 actor:=trujillo.current_actor(true);
 SELECT c.operator_id,c.decision INTO owner,decision
 FROM trujillo.sos_cases c WHERE c.id=p_id;
 IF owner IS NULL THEN
  SELECT s.operator_id INTO owner FROM trujillo.call_sessions s WHERE s.id=p_id;
 END IF;
 RETURN jsonb_build_object(
  'available',owner IS NULL AND coalesce(decision,'pending')='pending',
  'claimed_by_me',owner=actor AND coalesce(decision,'pending')='pending');
END; $$;
REVOKE ALL ON FUNCTION trujillo.sos_offer_status(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION trujillo.sos_offer_status(uuid) TO trujillo_api;
