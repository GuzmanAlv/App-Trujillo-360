ALTER TABLE trujillo.reports ADD COLUMN photo_manifest jsonb NOT NULL DEFAULT '[]';
CREATE TABLE trujillo.report_photos (
 id uuid PRIMARY KEY,
 report_id uuid NOT NULL REFERENCES trujillo.reports(id),
 position integer NOT NULL CHECK(position BETWEEN 0 AND 2),
 original_sha256 text NOT NULL CHECK(original_sha256 ~ '^[0-9a-f]{64}$'),
 content bytea NOT NULL CHECK(octet_length(content) BETWEEN 1 AND 2097152),
 UNIQUE(report_id, position)
);
ALTER TABLE trujillo.report_photos ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON trujillo.report_photos FROM PUBLIC, anon, authenticated;
GRANT SELECT ON trujillo.reports, trujillo.incidents, trujillo.report_photos TO trujillo_api;
CREATE POLICY report_owner_read ON trujillo.reports FOR SELECT TO trujillo_api USING (
 EXISTS(SELECT 1 FROM trujillo.users u WHERE u.id=user_id AND u.auth_provider='firebase'
 AND u.auth_subject=current_setting('app.firebase_uid',true) AND u.status='active')
);
CREATE POLICY incident_owner_read ON trujillo.incidents FOR SELECT TO trujillo_api USING (
 EXISTS(SELECT 1 FROM trujillo.reports r WHERE r.incident_id=trujillo.incidents.id)
);
CREATE POLICY photo_owner_read ON trujillo.report_photos FOR SELECT TO trujillo_api USING (
 EXISTS(SELECT 1 FROM trujillo.reports r WHERE r.id=trujillo.report_photos.report_id)
);

CREATE FUNCTION trujillo.submit_report_with_photos(p_request uuid, p_category text, p_place text,
 p_description text, p_lat double precision, p_lng double precision, p_time timestamptz, p_photos jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb; uid uuid; previous uuid; manifest jsonb; photo jsonb; idx integer := 0;
BEGIN
 SELECT id INTO uid FROM trujillo.users WHERE auth_provider='firebase'
 AND auth_subject=current_setting('app.firebase_uid',true) AND status='active' FOR SHARE;
 IF uid IS NULL THEN RAISE EXCEPTION 'Cuenta no disponible' USING ERRCODE='42501'; END IF;
 IF p_photos IS NULL OR jsonb_typeof(p_photos) <> 'array' THEN
   RAISE EXCEPTION 'Fotos invalidas' USING ERRCODE='22023';
 END IF;
 IF jsonb_array_length(p_photos) > 3 THEN
   RAISE EXCEPTION 'Demasiadas fotos' USING ERRCODE='22023';
 END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',value->>'id','sha256',value->>'sha256') ORDER BY ord), '[]')
 INTO manifest FROM jsonb_array_elements(p_photos) WITH ORDINALITY AS photos(value,ord);
 PERFORM pg_advisory_xact_lock(hashtextextended(uid::text || p_request::text,0));
 SELECT id INTO previous FROM trujillo.reports WHERE user_id=uid AND request_id=p_request;
 result := trujillo.submit_report(p_request,p_category,p_place,p_description,p_lat,p_lng,p_time);
 IF previous IS NOT NULL THEN
   IF (SELECT photo_manifest FROM trujillo.reports WHERE id=previous) IS DISTINCT FROM manifest THEN
     RAISE EXCEPTION 'Fotos modificadas en reintento' USING ERRCODE='P0001';
   END IF;
 ELSE
   UPDATE trujillo.reports SET photo_manifest=manifest WHERE id=(result->>'id')::uuid;
   FOR photo IN SELECT value FROM jsonb_array_elements(p_photos) LOOP
     INSERT INTO trujillo.report_photos(id,report_id,position,original_sha256,content)
     VALUES((photo->>'id')::uuid,(result->>'id')::uuid,idx,photo->>'sha256',decode(photo->>'content_base64','base64'));
     idx := idx+1;
   END LOOP;
 END IF;
 RETURN result || jsonb_build_object('photo_count',jsonb_array_length(manifest));
END;
$$;
REVOKE ALL ON FUNCTION trujillo.submit_report_with_photos(uuid,text,text,text,double precision,double precision,timestamptz,jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION trujillo.submit_report_with_photos(uuid,text,text,text,double precision,double precision,timestamptz,jsonb) TO trujillo_api;
INSERT INTO trujillo.schema_migrations(version) VALUES(4);
