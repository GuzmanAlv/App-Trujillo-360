-- Public incident summaries for map browsing; private reports and photos remain protected.
CREATE INDEX incidents_viewport_idx ON trujillo.incidents USING gist ((location::extensions.geometry))
 WHERE status IN ('pending','corroborated','verified');
CREATE FUNCTION trujillo.map_incidents(p_south double precision, p_north double precision,
 p_west double precision, p_east double precision)
RETURNS TABLE(id uuid, category text, latitude double precision, longitude double precision,
 occurred_at timestamptz, status text, corroboration_count integer, needs_review boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM trujillo.users u WHERE u.auth_provider='firebase'
 AND u.auth_subject=current_setting('app.firebase_uid',true) AND u.status='active') THEN
 RAISE EXCEPTION 'Cuenta no disponible' USING ERRCODE='42501'; END IF;
 IF p_south IS NULL OR p_north IS NULL OR p_west IS NULL OR p_east IS NULL
 OR NOT (p_south BETWEEN -90 AND 90) OR NOT (p_north BETWEEN -90 AND 90)
 OR p_south > p_north OR NOT (p_west BETWEEN -180 AND 180) OR NOT (p_east BETWEEN -180 AND 180) THEN
 RAISE EXCEPTION 'Área inválida' USING ERRCODE='22023'; END IF;
 RETURN QUERY SELECT i.id,i.category,extensions.ST_Y(i.location::extensions.geometry),
 extensions.ST_X(i.location::extensions.geometry),i.occurred_at,i.status,i.corroboration_count,i.needs_review
 FROM trujillo.incidents i WHERE i.status IN ('pending','corroborated','verified')
 AND i.occurred_at >= now()-interval '7 days'
 AND CASE WHEN p_west <= p_east THEN
 extensions.ST_Intersects(i.location::extensions.geometry,extensions.ST_MakeEnvelope(p_west,p_south,p_east,p_north,4326))
 ELSE
 (extensions.ST_Intersects(i.location::extensions.geometry,extensions.ST_MakeEnvelope(p_west,p_south,180,p_north,4326))
 OR extensions.ST_Intersects(i.location::extensions.geometry,extensions.ST_MakeEnvelope(-180,p_south,p_east,p_north,4326))) END
 ORDER BY i.occurred_at DESC,i.id LIMIT 500;
END;
$$;
REVOKE ALL ON FUNCTION trujillo.map_incidents(double precision,double precision,double precision,double precision) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION trujillo.map_incidents(double precision,double precision,double precision,double precision) TO trujillo_api;
INSERT INTO trujillo.schema_migrations(version) VALUES(9);
