-- Compatible extension of schema 11: old apps ignore the additional place field.
-- Keep schema_version=11 because the deployed API readiness requires exactly 11.
-- No identities or private descriptions are exposed. Apply in one transaction.
DROP FUNCTION trujillo.incident_reports(uuid);
CREATE FUNCTION trujillo.incident_reports(p_incident uuid)
RETURNS TABLE(id uuid, category text, latitude double precision, longitude double precision,
 occurred_at timestamptz, status text, corroboration_count integer, needs_review boolean, place text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM trujillo.users u WHERE u.auth_provider='firebase'
 AND u.auth_subject=current_setting('app.firebase_uid',true) AND u.status='active') THEN
 RAISE EXCEPTION 'Cuenta no disponible' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS (SELECT 1 FROM trujillo.incidents i WHERE i.id=p_incident
 AND i.status IN ('corroborated','verified') AND i.corroboration_count>=3
 AND NOT i.needs_review AND i.occurred_at>=now()-interval '7 days') THEN
 RAISE EXCEPTION 'Incidente no disponible' USING ERRCODE='P0002'; END IF;
 RETURN QUERY SELECT r.id,r.category,extensions.ST_Y(r.location::extensions.geometry),
 extensions.ST_X(r.location::extensions.geometry),r.occurred_at,i.status,i.corroboration_count,i.needs_review,r.place
 FROM trujillo.reports r JOIN trujillo.incidents i ON i.id=r.incident_id
 WHERE r.incident_id=p_incident AND r.withdrawn_at IS NULL
 ORDER BY r.occurred_at,r.id;
END;
$$;
REVOKE ALL ON FUNCTION trujillo.incident_reports(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION trujillo.incident_reports(uuid) TO trujillo_api;
