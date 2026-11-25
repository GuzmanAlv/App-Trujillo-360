-- Public SOS summaries within 1 km; no legacy reports or private caller fields.
CREATE FUNCTION trujillo.nearby_sos(p_lat double precision,p_lng double precision) RETURNS SETOF jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE point extensions.geography;
BEGIN
 PERFORM trujillo.current_actor(false);
 IF p_lat IS NULL OR p_lng IS NULL OR NOT(p_lat BETWEEN -90 AND 90) OR NOT(p_lng BETWEEN -180 AND 180) THEN
  RAISE EXCEPTION 'Coordenadas inválidas' USING ERRCODE='22023'; END IF;
 point:=extensions.ST_SetSRID(extensions.ST_MakePoint(p_lng,p_lat),4326)::extensions.geography;
 RETURN QUERY SELECT jsonb_build_object('id',i.id,'category',i.category,
  'latitude',extensions.ST_Y(i.location::extensions.geometry),'longitude',extensions.ST_X(i.location::extensions.geometry),
  'occurred_at',i.occurred_at,'status',i.status,'corroboration_count',i.corroboration_count,
  'needs_review',i.needs_review,'attention',i.attention,'resolved_at',i.resolved_at,
  'description',i.public_description,'place',nullif(i.public_place,''),'is_sos',true)
 FROM trujillo.incidents i
 WHERE EXISTS(SELECT 1 FROM trujillo.sos_cases c WHERE c.incident_id=i.id AND c.decision='confirmed')
 AND trujillo.map_incident_visible(i.status,i.corroboration_count,i.needs_review,i.occurred_at,i.resolved_at,i.was_public)
 AND extensions.ST_DWithin(i.location,point,1000)
 ORDER BY extensions.ST_Distance(i.location,point),i.id LIMIT 200;
END; $$;
REVOKE ALL ON FUNCTION trujillo.nearby_sos(double precision,double precision) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION trujillo.nearby_sos(double precision,double precision) TO trujillo_api;
