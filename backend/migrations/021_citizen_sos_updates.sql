-- Owner-scoped SOS follow-up. Evidence never enters public incident readers.
CREATE TABLE trujillo.sos_citizen_updates(
 id uuid PRIMARY KEY,
 case_id uuid NOT NULL REFERENCES trujillo.help_requests(id),
 description text NOT NULL CHECK(length(description)<=1000),
 photos jsonb NOT NULL DEFAULT '[]' CHECK(jsonb_typeof(photos)='array' AND jsonb_array_length(photos)<=3),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX sos_citizen_updates_case ON trujillo.sos_citizen_updates(case_id,created_at);
ALTER TABLE trujillo.sos_citizen_updates ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON trujillo.sos_citizen_updates FROM PUBLIC,anon,authenticated,trujillo_api;

CREATE FUNCTION trujillo.citizen_sos_cases(p_id uuid DEFAULT NULL) RETURNS SETOF jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid;
BEGIN
 actor:=trujillo.current_actor(false);
 RETURN QUERY SELECT jsonb_build_object('id',h.id,'category',c.category,'latitude',c.latitude,'longitude',c.longitude,
 'decision',c.decision,'attention',c.attention,'incident_id',c.incident_id,'description',c.public_description,'place',c.place,
 'received_at',h.received_at,'can_contribute',h.received_at>=now()-interval '7 days')
 FROM trujillo.help_requests h JOIN trujillo.sos_cases c ON c.id=h.id
 WHERE h.user_id=actor AND h.source='sos' AND c.decision='confirmed'
 AND ((p_id IS NULL AND c.attention<>'resolved' AND h.stage NOT IN ('Cerrada','Descartada')) OR h.id=p_id)
 ORDER BY h.received_at DESC LIMIT 200;
END; $$;

CREATE FUNCTION trujillo.sos_evidence_access(p_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid;
BEGIN
 actor:=trujillo.current_actor(false);
 IF NOT EXISTS(SELECT 1 FROM trujillo.help_requests h WHERE h.id=p_id AND h.source='sos' AND
 (h.user_id=actor OR EXISTS(SELECT 1 FROM trujillo.users u WHERE u.id=actor AND u.role IN ('operator','admin')))) THEN
  RAISE EXCEPTION 'Caso no disponible' USING ERRCODE='42501'; END IF;
END; $$;

CREATE FUNCTION trujillo.sos_citizen_evidence(p_id uuid) RETURNS SETOF jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM trujillo.sos_evidence_access(p_id);
 RETURN QUERY SELECT jsonb_build_object('id',e.id,'description',e.description,'at',e.created_at,
 'photos',coalesce((SELECT jsonb_agg(jsonb_build_object('id',p->>'id')) FROM jsonb_array_elements(e.photos) p),'[]'::jsonb))
 FROM trujillo.sos_citizen_updates e WHERE e.case_id=p_id ORDER BY e.created_at,e.id;
END; $$;

CREATE FUNCTION trujillo.sos_citizen_submit(p_id uuid,p_request uuid,p_description text,p_photos jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; h trujillo.help_requests; old trujillo.sos_citizen_updates; photo jsonb;
BEGIN
 actor:=trujillo.current_actor(false);
 SELECT * INTO h FROM trujillo.help_requests WHERE id=p_id AND source='sos' AND user_id=actor FOR UPDATE;
 IF h.id IS NULL THEN RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501'; END IF;
 SELECT * INTO old FROM trujillo.sos_citizen_updates WHERE id=p_request;
 IF old.id IS NOT NULL THEN
  IF (old.case_id,old.description,old.photos) IS DISTINCT FROM (p_id,p_description,p_photos) THEN RAISE EXCEPTION 'Reintento diferente'; END IF;
  RETURN jsonb_build_object('id',old.id); END IF;
 IF NOT EXISTS(SELECT 1 FROM trujillo.sos_cases WHERE id=p_id AND decision='confirmed')
 OR h.received_at<now()-interval '7 days' THEN RAISE EXCEPTION 'No se admiten aportes en este caso' USING ERRCODE='22023'; END IF;
 IF p_request IS NULL OR p_description IS NULL OR length(p_description)>1000
 OR p_photos IS NULL OR jsonb_typeof(p_photos)<>'array' OR jsonb_array_length(p_photos)>3
 OR (length(trim(p_description))=0 AND jsonb_array_length(p_photos)=0) THEN
  RAISE EXCEPTION 'Aporte vacío o inválido' USING ERRCODE='22023'; END IF;
 IF (SELECT count(*) FROM trujillo.sos_citizen_updates WHERE case_id=p_id)>=30
 OR (SELECT coalesce(sum(jsonb_array_length(photos)),0) FROM trujillo.sos_citizen_updates WHERE case_id=p_id)+jsonb_array_length(p_photos)>3 THEN
  RAISE EXCEPTION 'Límite de aportes' USING ERRCODE='22023'; END IF;
 IF (SELECT count(DISTINCT p->>'id') FROM jsonb_array_elements(p_photos) p)<>jsonb_array_length(p_photos) THEN
  RAISE EXCEPTION 'Fotos repetidas' USING ERRCODE='22023'; END IF;
 FOR photo IN SELECT value FROM jsonb_array_elements(p_photos) LOOP
  IF photo->>'id' IS NULL OR photo->>'sha256' IS NULL OR photo->>'content_base64' IS NULL
  OR length(photo->>'content_base64')>2796204 OR octet_length(decode(photo->>'content_base64','base64')) NOT BETWEEN 1 AND 2097152 THEN
   RAISE EXCEPTION 'Foto inválida' USING ERRCODE='22023'; END IF;
  IF EXISTS(SELECT 1 FROM trujillo.sos_citizen_updates e CROSS JOIN LATERAL jsonb_array_elements(e.photos) p
   WHERE e.case_id=p_id AND p->>'id'=photo->>'id') THEN RAISE EXCEPTION 'Foto reutilizada'; END IF;
 END LOOP;
 INSERT INTO trujillo.sos_citizen_updates(id,case_id,description,photos) VALUES(p_request,p_id,p_description,p_photos);
 RETURN jsonb_build_object('id',p_request);
END; $$;

CREATE FUNCTION trujillo.sos_citizen_photo(p_id uuid,p_photo uuid) RETURNS bytea
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE content bytea;
BEGIN
 PERFORM trujillo.sos_evidence_access(p_id);
 SELECT decode(p->>'content_base64','base64') INTO content FROM trujillo.sos_citizen_updates e
 CROSS JOIN LATERAL jsonb_array_elements(e.photos) p WHERE e.case_id=p_id AND p->>'id'=p_photo::text;
 IF content IS NULL THEN RAISE EXCEPTION 'Foto no disponible' USING ERRCODE='P0002'; END IF;
 RETURN content;
END; $$;
REVOKE ALL ON FUNCTION trujillo.citizen_sos_cases(uuid),trujillo.sos_evidence_access(uuid),trujillo.sos_citizen_evidence(uuid),
 trujillo.sos_citizen_submit(uuid,uuid,text,jsonb),trujillo.sos_citizen_photo(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION trujillo.citizen_sos_cases(uuid),trujillo.sos_citizen_evidence(uuid),
 trujillo.sos_citizen_submit(uuid,uuid,text,jsonb),trujillo.sos_citizen_photo(uuid,uuid) TO trujillo_api;
