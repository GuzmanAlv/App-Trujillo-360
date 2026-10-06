ALTER TABLE trujillo.incidents ADD COLUMN corroboration_count integer NOT NULL DEFAULT 0 CHECK(corroboration_count >= 0);
ALTER TABLE trujillo.incidents ADD COLUMN needs_review boolean NOT NULL DEFAULT false;
UPDATE trujillo.incidents i SET corroboration_count=(
 SELECT count(DISTINCT r.user_id) FROM trujillo.reports r
 WHERE r.incident_id=i.id AND r.withdrawn_at IS NULL);

CREATE OR REPLACE FUNCTION trujillo.submit_report(p_request uuid, p_category text, p_place text,
 p_description text, p_lat double precision, p_lng double precision, p_time timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE u trujillo.users; r trujillo.reports; chosen uuid; matches uuid[];
 point extensions.geography; amount integer;
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
     OR NOT (p_lng BETWEEN -180 AND 180) OR p_time IS NULL
     OR p_time > now() + interval '5 minutes' OR p_time < now() - interval '7 days' THEN
     RAISE EXCEPTION 'Datos invalidos' USING ERRCODE='22023';
   END IF;
   point := extensions.ST_SetSRID(extensions.ST_MakePoint(p_lng,p_lat),4326)::extensions.geography;
   -- Serializes candidate selection + insertion per category, including when
   -- no candidate exists. Prevents two concurrent first reports splitting a group.
   PERFORM pg_advisory_xact_lock(hashtextextended('trujillo.match.' || p_category, 0));
   SELECT array_agg(i.id ORDER BY i.id) INTO matches FROM trujillo.incidents i
   WHERE i.category=p_category AND i.status IN ('pending','corroborated')
     AND NOT i.needs_review
     AND p_time BETWEEN i.occurred_at AND i.occurred_at + interval '15 minutes'
     AND extensions.ST_DWithin(i.location, point, 100);
   IF cardinality(matches)=1 THEN
     chosen := matches[1];
     IF EXISTS(SELECT 1 FROM trujillo.reports WHERE incident_id=chosen AND user_id=u.id) THEN
       RAISE EXCEPTION 'Ya aportaste a este incidente' USING ERRCODE='P0002';
     END IF;
   ELSE
     -- Ambiguous matches remain separate for later operator review.
     INSERT INTO trujillo.incidents(category, location, occurred_at, needs_review)
     VALUES (p_category, point, p_time, coalesce(cardinality(matches),0)>1)
     RETURNING id INTO chosen;
   END IF;
   INSERT INTO trujillo.reports(user_id,incident_id,request_id,category,place,description,location,occurred_at)
   VALUES (u.id,chosen,p_request,p_category,p_place,p_description,point,p_time)
   RETURNING * INTO r;
   SELECT count(DISTINCT user_id) INTO amount FROM trujillo.reports
     WHERE incident_id=chosen AND withdrawn_at IS NULL;
   UPDATE trujillo.incidents SET corroboration_count=amount,
     status=CASE WHEN status='pending' AND amount>=3 AND NOT needs_review
       THEN 'corroborated' ELSE status END, updated_at=now()
     WHERE id=chosen;
 END IF;
 RETURN (SELECT jsonb_build_object('id',r.id,'incident_id',r.incident_id,'request_id',r.request_id,
   'status',i.status,'corroboration_count',i.corroboration_count,'needs_review',i.needs_review)
   FROM trujillo.incidents i WHERE i.id=r.incident_id);
END;
$$;
INSERT INTO trujillo.schema_migrations(version) VALUES(5);
