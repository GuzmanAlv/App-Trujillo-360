-- Community feed exposes incident summaries, never owners or private photos.
CREATE FUNCTION trujillo.nearby_incidents(p_lat double precision, p_lng double precision, p_radius integer)
RETURNS TABLE(id uuid, category text, latitude double precision, longitude double precision,
 occurred_at timestamptz, status text, corroboration_count integer, needs_review boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE point extensions.geography;
BEGIN
 IF NOT EXISTS (SELECT 1 FROM trujillo.users WHERE auth_provider='firebase'
 AND auth_subject=current_setting('app.firebase_uid',true) AND status='active') THEN
 RAISE EXCEPTION 'Cuenta no disponible' USING ERRCODE='42501';
 END IF;
 IF p_lat IS NULL OR p_lng IS NULL OR p_radius IS NULL OR NOT (p_lat BETWEEN -90 AND 90)
 OR NOT (p_lng BETWEEN -180 AND 180) OR NOT (p_radius BETWEEN 100 AND 3000) THEN
 RAISE EXCEPTION 'Coordenadas inválidas' USING ERRCODE='22023';
 END IF;
 point := extensions.ST_SetSRID(extensions.ST_MakePoint(p_lng,p_lat),4326)::extensions.geography;
 RETURN QUERY SELECT i.id,i.category,extensions.ST_Y(i.location::extensions.geometry),
 extensions.ST_X(i.location::extensions.geometry),i.occurred_at,i.status,i.corroboration_count,i.needs_review
 FROM trujillo.incidents i WHERE i.status IN ('pending','corroborated','verified')
 AND i.occurred_at >= now()-interval '7 days'
 AND extensions.ST_DWithin(i.location,point,p_radius)
 ORDER BY extensions.ST_Distance(i.location,point),i.id LIMIT 200;
END;
$$;
REVOKE ALL ON FUNCTION trujillo.nearby_incidents(double precision,double precision,integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION trujillo.nearby_incidents(double precision,double precision,integer) TO trujillo_api;
INSERT INTO trujillo.schema_migrations(version) VALUES(6);
