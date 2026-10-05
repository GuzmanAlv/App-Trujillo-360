-- Only the backend role can execute this atomic operation. No Data API access.
CREATE FUNCTION trujillo.submit_report(p_request uuid, p_category text, p_place text,
 p_description text, p_lat double precision, p_lng double precision, p_time timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE u trujillo.users; r trujillo.reports; incident uuid;
BEGIN
 SELECT * INTO u FROM trujillo.users WHERE auth_provider='firebase'
 AND auth_subject=current_setting('app.firebase_uid', true) FOR SHARE;
 IF u.id IS NULL OR u.status <> 'active' THEN
   RAISE EXCEPTION 'Cuenta no disponible' USING ERRCODE='42501';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(u.id::text || p_request::text, 0));
 SELECT * INTO r FROM trujillo.reports WHERE user_id=u.id AND request_id=p_request;
 IF r.id IS NOT NULL THEN
   IF r.category IS DISTINCT FROM p_category OR r.place IS DISTINCT FROM p_place
     OR r.description IS DISTINCT FROM p_description OR r.occurred_at IS DISTINCT FROM p_time
     OR extensions.ST_Y(r.location::extensions.geometry) IS DISTINCT FROM p_lat
     OR extensions.ST_X(r.location::extensions.geometry) IS DISTINCT FROM p_lng THEN
     RAISE EXCEPTION 'Solicitud reutilizada con datos diferentes' USING ERRCODE='P0001';
   END IF;
 ELSE
   IF p_lat IS NULL OR p_lng IS NULL OR NOT (p_lat BETWEEN -90 AND 90)
     OR NOT (p_lng BETWEEN -180 AND 180) OR p_time > now() + interval '5 minutes'
     OR p_time < now() - interval '7 days' THEN
     RAISE EXCEPTION 'Datos invalidos' USING ERRCODE='22023';
   END IF;
   INSERT INTO trujillo.incidents(category, location, occurred_at)
   VALUES (p_category, extensions.ST_SetSRID(extensions.ST_MakePoint(p_lng,p_lat),4326)::extensions.geography,p_time)
   RETURNING id INTO incident;
   INSERT INTO trujillo.reports(user_id,incident_id,request_id,category,place,description,location,occurred_at)
   VALUES (u.id,incident,p_request,p_category,p_place,p_description,
     extensions.ST_SetSRID(extensions.ST_MakePoint(p_lng,p_lat),4326)::extensions.geography,p_time)
   RETURNING * INTO r;
 END IF;
 RETURN jsonb_build_object('id',r.id,'incident_id',r.incident_id,'request_id',r.request_id,
   'status',(SELECT status FROM trujillo.incidents WHERE id=r.incident_id));
END;
$$;
REVOKE ALL ON FUNCTION trujillo.submit_report(uuid,text,text,text,double precision,double precision,timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION trujillo.submit_report(uuid,text,text,text,double precision,double precision,timestamptz) TO trujillo_api;
INSERT INTO trujillo.schema_migrations(version) VALUES(3);
