-- Operator pilot: cameras and access are provisioned by an administrator.
CREATE TABLE trujillo.ai_migrations(version integer PRIMARY KEY);
CREATE TABLE trujillo.ai_cameras(
 id text PRIMARY KEY CHECK(length(trim(id)) BETWEEN 1 AND 200),
 active boolean NOT NULL DEFAULT true);
CREATE TABLE trujillo.ai_camera_access(
 camera_id text REFERENCES trujillo.ai_cameras(id),
 operator_id uuid REFERENCES trujillo.users(id),
 PRIMARY KEY(camera_id,operator_id));
CREATE TABLE trujillo.ai_candidates(
 sequence bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 id text UNIQUE NOT NULL,
 camera_id text NOT NULL REFERENCES trujillo.ai_cameras(id),
 payload jsonb NOT NULL,
 submitted_by uuid NOT NULL REFERENCES trujillo.users(id),
 received_at timestamptz NOT NULL DEFAULT now(),
 status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','confirmed','discarded')),
 reviewed_by uuid REFERENCES trujillo.users(id),
 reviewed_at timestamptz, reason text);
CREATE INDEX ai_camera_queue ON trujillo.ai_candidates(camera_id,sequence DESC);
ALTER TABLE trujillo.ai_migrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE trujillo.ai_cameras ENABLE ROW LEVEL SECURITY;
ALTER TABLE trujillo.ai_camera_access ENABLE ROW LEVEL SECURITY;
ALTER TABLE trujillo.ai_candidates ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON trujillo.ai_migrations,trujillo.ai_cameras,trujillo.ai_camera_access,trujillo.ai_candidates FROM PUBLIC,anon,authenticated,trujillo_api;
GRANT SELECT ON trujillo.ai_migrations TO trujillo_api;
CREATE POLICY ai_version_read ON trujillo.ai_migrations FOR SELECT TO trujillo_api USING(true);

CREATE FUNCTION trujillo.ai_camera_allowed(p_camera text,p_actor uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM trujillo.ai_cameras c WHERE c.id=p_camera AND c.active
 AND (EXISTS(SELECT 1 FROM trujillo.users u WHERE u.id=p_actor AND u.role='admin' AND u.status='active')
 OR EXISTS(SELECT 1 FROM trujillo.ai_camera_access a WHERE a.camera_id=c.id AND a.operator_id=p_actor)));
$$;
CREATE FUNCTION trujillo.ai_candidate_json(p_row trujillo.ai_candidates) RETURNS jsonb
LANGUAGE sql STABLE SET search_path='' AS $$
 SELECT p_row.payload || jsonb_build_object('sequence',p_row.sequence,'status',p_row.status,
 'receivedAt',p_row.received_at,'reviewedBy',p_row.reviewed_by,'reviewedAt',p_row.reviewed_at,'reason',p_row.reason);
$$;
CREATE FUNCTION trujillo.submit_ai_candidate(p_data jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; result trujillo.ai_candidates;
BEGIN
 actor:=trujillo.current_actor(true);
 IF NOT trujillo.ai_camera_allowed(p_data->>'cameraId',actor) THEN
  RAISE EXCEPTION 'Camera access denied' USING ERRCODE='42501'; END IF;
 IF p_data IS NULL OR NOT(p_data ?& ARRAY['schemaVersion','type','id','cameraId','modelVersion','confidence','latitude','longitude','detectedAt'])
 OR p_data->>'schemaVersion' IS DISTINCT FROM '1' OR p_data->>'type' IS DISTINCT FROM 'aggression_candidate'
 OR jsonb_typeof(p_data->'id') IS DISTINCT FROM 'string'
 OR length(trim(p_data->>'id')) NOT BETWEEN 1 AND 200
 OR jsonb_typeof(p_data->'modelVersion') IS DISTINCT FROM 'string'
 OR length(trim(p_data->>'modelVersion')) NOT BETWEEN 1 AND 200
 OR jsonb_typeof(p_data->'confidence') IS DISTINCT FROM 'number'
 OR jsonb_typeof(p_data->'latitude') IS DISTINCT FROM 'number'
 OR jsonb_typeof(p_data->'longitude') IS DISTINCT FROM 'number'
 OR jsonb_typeof(p_data->'detectedAt') IS DISTINCT FROM 'string'
 OR NOT((p_data->>'confidence')::double precision BETWEEN 0 AND 1)
 OR NOT((p_data->>'latitude')::double precision BETWEEN -90 AND 90)
 OR NOT((p_data->>'longitude')::double precision BETWEEN -180 AND 180)
 OR (p_data->>'detectedAt') !~ '(Z|[+-][0-9]{2}:[0-9]{2})$'
 OR (p_data->>'detectedAt')::timestamptz > now()+interval '5 minutes'
 THEN RAISE EXCEPTION 'Invalid candidate' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_data->>'id',360017));
 SELECT * INTO result FROM trujillo.ai_candidates WHERE id=p_data->>'id';
 IF FOUND THEN
  IF result.payload IS DISTINCT FROM p_data THEN RAISE EXCEPTION 'Immutable candidate' USING ERRCODE='P0001'; END IF;
  RETURN trujillo.ai_candidate_json(result);
 END IF;
 INSERT INTO trujillo.ai_candidates(id,camera_id,payload,submitted_by)
 VALUES(p_data->>'id',p_data->>'cameraId',p_data,actor) RETURNING * INTO result;
 RETURN trujillo.ai_candidate_json(result);
END; $$;
CREATE FUNCTION trujillo.list_ai_candidates(p_before bigint,p_limit integer) RETURNS SETOF jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid;
BEGIN
 actor:=trujillo.current_actor(true);
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 101 OR p_before<1 THEN
  RAISE EXCEPTION 'Invalid pagination' USING ERRCODE='22023'; END IF;
 RETURN QUERY SELECT trujillo.ai_candidate_json(c) FROM trujillo.ai_candidates c
 WHERE (p_before IS NULL OR c.sequence<p_before) AND trujillo.ai_camera_allowed(c.camera_id,actor)
 ORDER BY c.sequence DESC LIMIT p_limit;
END; $$;
CREATE FUNCTION trujillo.review_ai_candidate(p_sequence bigint,p_decision text,p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; result trujillo.ai_candidates;
BEGIN
 actor:=trujillo.current_actor(true);
 SELECT * INTO result FROM trujillo.ai_candidates WHERE sequence=p_sequence FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Unavailable' USING ERRCODE='P0002'; END IF;
 IF NOT trujillo.ai_camera_allowed(result.camera_id,actor) THEN
  RAISE EXCEPTION 'Camera access denied' USING ERRCODE='42501'; END IF;
 IF p_decision IS NULL OR p_decision NOT IN ('confirmed','discarded') OR p_reason IS NULL
 OR length(trim(p_reason)) NOT BETWEEN 5 AND 500 THEN
  RAISE EXCEPTION 'Invalid decision' USING ERRCODE='22023'; END IF;
 IF result.status<>'pending' THEN
  IF (result.status,result.reviewed_by,result.reason) IS DISTINCT FROM (p_decision,actor,trim(p_reason)) THEN
   RAISE EXCEPTION 'Already reviewed' USING ERRCODE='P0001'; END IF;
  RETURN trujillo.ai_candidate_json(result);
 END IF;
 UPDATE trujillo.ai_candidates SET status=p_decision,reviewed_by=actor,reviewed_at=now(),reason=trim(p_reason)
 WHERE sequence=p_sequence RETURNING * INTO result;
 RETURN trujillo.ai_candidate_json(result);
END; $$;
REVOKE ALL ON FUNCTION trujillo.ai_camera_allowed(text,uuid),trujillo.ai_candidate_json(trujillo.ai_candidates),trujillo.submit_ai_candidate(jsonb),trujillo.list_ai_candidates(bigint,integer),trujillo.review_ai_candidate(bigint,text,text) FROM PUBLIC,anon,authenticated,trujillo_api;
GRANT EXECUTE ON FUNCTION trujillo.submit_ai_candidate(jsonb),trujillo.list_ai_candidates(bigint,integer),trujillo.review_ai_candidate(bigint,text,text) TO trujillo_api;
INSERT INTO trujillo.ai_migrations VALUES(1);
