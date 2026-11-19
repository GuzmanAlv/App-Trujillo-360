-- Public resolved incidents remain on the map for seven days after closure.
ALTER TABLE trujillo.incidents ADD COLUMN resolved_at timestamptz;
UPDATE trujillo.incidents SET resolved_at=updated_at WHERE status='closed' AND was_public;
CREATE FUNCTION trujillo.track_incident_resolution() RETURNS trigger
LANGUAGE plpgsql SET search_path='' AS $$ BEGIN
 IF NEW.status='closed' AND (TG_OP='INSERT' OR OLD.status IS DISTINCT FROM 'closed') THEN
  NEW.resolved_at=now();
 ELSIF NEW.status<>'closed' THEN NEW.resolved_at=NULL;
 ELSE NEW.resolved_at=OLD.resolved_at; END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER track_incident_resolution BEFORE INSERT OR UPDATE ON trujillo.incidents
FOR EACH ROW EXECUTE FUNCTION trujillo.track_incident_resolution();
REVOKE ALL ON FUNCTION trujillo.track_incident_resolution() FROM PUBLIC,anon,authenticated;
CREATE FUNCTION trujillo.map_incident_visible(p_status text,p_count integer,p_review boolean,
 p_occurred timestamptz,p_resolved timestamptz,p_was_public boolean) RETURNS boolean
LANGUAGE sql STABLE SET search_path='' AS $$ SELECT p_occurred<=now() AND (
 (trujillo.is_public_incident(p_status,p_count,p_review) AND p_occurred>now()-interval '7 days') OR
 (p_status='closed' AND p_was_public AND NOT p_review AND p_resolved<=now() AND p_resolved>now()-interval '7 days')) $$;
REVOKE ALL ON FUNCTION trujillo.map_incident_visible(text,integer,boolean,timestamptz,timestamptz,boolean) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION trujillo.public_case_fields(p_ids uuid[]) RETURNS SETOF jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM trujillo.current_actor(false);
 RETURN QUERY SELECT jsonb_build_object('id',i.id,'description',i.public_description,
 'place',nullif(i.public_place,''),'attention',i.attention,'resolved_at',i.resolved_at)
 FROM trujillo.incidents i WHERE i.id=ANY(p_ids)
 AND trujillo.map_incident_visible(i.status,i.corroboration_count,i.needs_review,i.occurred_at,i.resolved_at,i.was_public);
END; $$;

CREATE OR REPLACE FUNCTION trujillo.nearby_incidents(p_lat double precision, p_lng double precision, p_radius integer)
RETURNS TABLE(id uuid, category text, latitude double precision, longitude double precision,
 occurred_at timestamptz, status text, corroboration_count integer, needs_review boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE point extensions.geography;
BEGIN
 IF NOT EXISTS (SELECT 1 FROM trujillo.users u WHERE u.auth_provider='firebase'
 AND u.auth_subject=current_setting('app.firebase_uid',true) AND u.status='active') THEN
 RAISE EXCEPTION 'Cuenta no disponible' USING ERRCODE='42501';
 END IF;
 IF p_lat IS NULL OR p_lng IS NULL OR p_radius IS NULL OR NOT (p_lat BETWEEN -90 AND 90)
 OR NOT (p_lng BETWEEN -180 AND 180) OR NOT (p_radius BETWEEN 100 AND 3000) THEN
 RAISE EXCEPTION 'Coordenadas inválidas' USING ERRCODE='22023';
 END IF;
 point := extensions.ST_SetSRID(extensions.ST_MakePoint(p_lng,p_lat),4326)::extensions.geography;
 RETURN QUERY SELECT i.id,i.category,extensions.ST_Y(i.location::extensions.geometry),
 extensions.ST_X(i.location::extensions.geometry),i.occurred_at,i.status,i.corroboration_count,i.needs_review
 FROM trujillo.incidents i WHERE trujillo.map_incident_visible(i.status,i.corroboration_count,i.needs_review,i.occurred_at,i.resolved_at,i.was_public)
 AND extensions.ST_DWithin(i.location,point,p_radius)
 ORDER BY extensions.ST_Distance(i.location,point),i.id LIMIT 200;
END;
$$;

CREATE OR REPLACE FUNCTION trujillo.map_incidents(p_south double precision, p_north double precision,
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
 FROM trujillo.incidents i WHERE trujillo.map_incident_visible(i.status,i.corroboration_count,i.needs_review,i.occurred_at,i.resolved_at,i.was_public)
 AND CASE WHEN p_west <= p_east THEN
 extensions.ST_Intersects(i.location::extensions.geometry,extensions.ST_MakeEnvelope(p_west,p_south,p_east,p_north,4326))
 ELSE
 (extensions.ST_Intersects(i.location::extensions.geometry,extensions.ST_MakeEnvelope(p_west,p_south,180,p_north,4326))
 OR extensions.ST_Intersects(i.location::extensions.geometry,extensions.ST_MakeEnvelope(-180,p_south,p_east,p_north,4326))) END
 ORDER BY i.occurred_at DESC,i.id LIMIT 500;
END;
$$;

CREATE OR REPLACE FUNCTION trujillo.incident_reports(p_incident uuid)
RETURNS TABLE(id uuid, category text, latitude double precision, longitude double precision,
 occurred_at timestamptz, status text, corroboration_count integer, needs_review boolean, place text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM trujillo.users u WHERE u.auth_provider='firebase'
 AND u.auth_subject=current_setting('app.firebase_uid',true) AND u.status='active') THEN
 RAISE EXCEPTION 'Cuenta no disponible' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS (SELECT 1 FROM trujillo.incidents i WHERE i.id=p_incident
 AND trujillo.map_incident_visible(i.status,i.corroboration_count,i.needs_review,i.occurred_at,i.resolved_at,i.was_public)) THEN
 RAISE EXCEPTION 'Incidente no disponible' USING ERRCODE='P0002'; END IF;
 RETURN QUERY SELECT r.id,r.category,extensions.ST_Y(r.location::extensions.geometry),
 extensions.ST_X(r.location::extensions.geometry),r.occurred_at,i.status,i.corroboration_count,i.needs_review,r.place
 FROM trujillo.reports r JOIN trujillo.incidents i ON i.id=r.incident_id
 WHERE r.incident_id=p_incident AND r.withdrawn_at IS NULL
 ORDER BY r.occurred_at,r.id;
END;
$$;
CREATE FUNCTION trujillo.resolved_map_version() RETURNS integer
LANGUAGE sql IMMUTABLE SET search_path='' AS $$ SELECT 1 $$;
REVOKE ALL ON FUNCTION trujillo.resolved_map_version() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION trujillo.resolved_map_version() TO trujillo_api;
