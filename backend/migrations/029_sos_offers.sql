-- Claim one pending SOS before opening its evaluation. The existing call lock
-- serializes this with call acceptance and case updates.
CREATE FUNCTION trujillo.claim_sos(p_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor trujillo.users; h trujillo.help_requests; owner uuid;
BEGIN
 SELECT * INTO actor FROM trujillo.users WHERE id=trujillo.current_actor(true);
 IF actor.role NOT IN ('operator','admin') THEN
  RAISE EXCEPTION 'Operador requerido' USING ERRCODE='42501'; END IF;
 PERFORM pg_advisory_xact_lock(360017);
 SELECT * INTO h FROM trujillo.help_requests WHERE id=p_id AND source='sos' FOR UPDATE;
 IF h.id IS NULL OR h.stage IN ('Cerrada','Descartada') OR h.user_id=actor.id THEN
  RAISE EXCEPTION 'SOS no disponible' USING ERRCODE='P0002'; END IF;
 SELECT coalesce(cs.operator_id,c.operator_id) INTO owner
 FROM trujillo.call_sessions c LEFT JOIN trujillo.sos_cases cs ON cs.id=c.id
 WHERE c.id=p_id;
 IF owner IS NULL THEN
  SELECT operator_id INTO owner FROM trujillo.sos_cases WHERE id=p_id;
 END IF;
 IF owner IS NOT NULL AND owner<>actor.id THEN
  RAISE EXCEPTION 'SOS tomado por otro operador' USING ERRCODE='P0001'; END IF;
 IF EXISTS(SELECT 1 FROM trujillo.sos_cases WHERE operator_id=actor.id
  AND id<>p_id AND decision='confirmed' AND attention IN ('en_route','on_scene')) THEN
  RAISE EXCEPTION 'Operador ocupado' USING ERRCODE='P0001'; END IF;
 INSERT INTO trujillo.sos_cases(id,operator_id,category,latitude,longitude)
 VALUES(p_id,actor.id,h.category,h.latitude,h.longitude)
 ON CONFLICT(id) DO NOTHING;
 UPDATE trujillo.help_requests SET stage='En revisión'
 WHERE id=p_id AND stage='Recibida';
 RETURN trujillo.sos_case_read(p_id);
END; $$;
REVOKE ALL ON FUNCTION trujillo.claim_sos(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION trujillo.claim_sos(uuid) TO trujillo_api;

CREATE FUNCTION trujillo.sos_offers_version() RETURNS integer
LANGUAGE sql IMMUTABLE SET search_path='' AS $$ SELECT 1 $$;
REVOKE ALL ON FUNCTION trujillo.sos_offers_version() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION trujillo.sos_offers_version() TO trujillo_api;
