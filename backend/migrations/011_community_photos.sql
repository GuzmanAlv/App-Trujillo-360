-- Photos are released only through corroborated community incidents.
CREATE FUNCTION trujillo.community_photos(p_incident uuid)
RETURNS TABLE(id uuid, report_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM 1 FROM trujillo.incident_reports(p_incident);
 RETURN QUERY SELECT p.id,p.report_id FROM trujillo.report_photos p
 JOIN trujillo.reports r ON r.id=p.report_id
 WHERE r.incident_id=p_incident AND r.withdrawn_at IS NULL
 ORDER BY r.occurred_at,r.id,p.position;
END;
$$;
CREATE FUNCTION trujillo.community_photo(p_incident uuid, p_photo uuid)
RETURNS bytea LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE image bytea;
BEGIN
 -- Re-check account, corroboration and incident visibility on every image read.
 PERFORM 1 FROM trujillo.incident_reports(p_incident);
 SELECT p.content INTO image FROM trujillo.report_photos p
 JOIN trujillo.reports r ON r.id=p.report_id
 WHERE p.id=p_photo AND r.incident_id=p_incident AND r.withdrawn_at IS NULL;
 IF image IS NULL THEN RAISE EXCEPTION 'Foto no disponible' USING ERRCODE='P0002'; END IF;
 RETURN image;
END;
$$;
REVOKE ALL ON FUNCTION trujillo.community_photos(uuid), trujillo.community_photo(uuid,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION trujillo.community_photos(uuid), trujillo.community_photo(uuid,uuid) TO trujillo_api;
INSERT INTO trujillo.schema_migrations(version) VALUES(11);
