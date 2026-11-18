-- Private audio sessions; no direct table access from API clients.
CREATE TABLE trujillo.call_sessions (
 id uuid PRIMARY KEY REFERENCES trujillo.help_requests(id),
 citizen_id uuid NOT NULL REFERENCES trujillo.users(id),
 operator_id uuid REFERENCES trujillo.users(id),
 state text NOT NULL DEFAULT 'waiting' CHECK(state IN ('waiting','accepted','ended','unanswered')),
 created_at timestamptz NOT NULL DEFAULT now(),
 accepted_at timestamptz, ended_at timestamptz,
 expires_at timestamptz NOT NULL DEFAULT now()+interval '90 seconds'
);
CREATE INDEX call_sessions_active_expiry ON trujillo.call_sessions(expires_at)
 WHERE state IN ('waiting','accepted');
ALTER TABLE trujillo.call_sessions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON trujillo.call_sessions FROM PUBLIC,anon,authenticated,trujillo_api;

CREATE FUNCTION trujillo.call_action(p_id uuid,p_action text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; h trujillo.help_requests; c trujillo.call_sessions; is_op boolean;
BEGIN
 actor:=trujillo.current_actor(false);
 SELECT role IN ('operator','admin') INTO is_op FROM trujillo.users WHERE id=actor;
 -- Serializes assignment and busy checks across sessions.
 PERFORM pg_advisory_xact_lock(360017);
 SELECT * INTO h FROM trujillo.help_requests WHERE id=p_id;
 IF NOT FOUND OR h.source<>'sos' OR (h.user_id<>actor AND NOT is_op) THEN
  RAISE EXCEPTION 'No disponible' USING ERRCODE='42501'; END IF;
 UPDATE trujillo.call_sessions SET state=CASE WHEN state='waiting' THEN 'unanswered' ELSE 'ended' END,
 ended_at=now() WHERE state IN ('waiting','accepted') AND expires_at<=now();
 IF p_action='start' THEN
  IF h.user_id<>actor OR h.stage IN ('Cerrada','Descartada') THEN
   RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501'; END IF;
  IF NOT EXISTS(SELECT 1 FROM trujillo.call_sessions WHERE id=p_id) THEN
   IF EXISTS(SELECT 1 FROM trujillo.call_sessions WHERE state IN ('waiting','accepted') AND (citizen_id=actor OR operator_id=actor)) THEN
    RAISE EXCEPTION 'Ya hay una llamada activa' USING ERRCODE='P0001'; END IF;
   INSERT INTO trujillo.call_sessions(id,citizen_id) VALUES(p_id,actor);
   INSERT INTO trujillo.help_events(request_id,actor_id,stage,priority,reason)
   VALUES(p_id,actor,h.stage,h.priority,'Solicitud de llamada de voz creada.');
  END IF;
 END IF;
 SELECT * INTO c FROM trujillo.call_sessions WHERE id=p_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Sin llamada' USING ERRCODE='P0002'; END IF;
 IF p_action='accept' THEN
  IF NOT is_op OR actor=c.citizen_id THEN RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501'; END IF;
  IF c.state='waiting' AND h.stage NOT IN ('Cerrada','Descartada') THEN
   IF EXISTS(SELECT 1 FROM trujillo.call_sessions WHERE id<>p_id AND state IN ('waiting','accepted') AND (operator_id=actor OR citizen_id=actor)) THEN
    RAISE EXCEPTION 'Operador ocupado' USING ERRCODE='P0001'; END IF;
   UPDATE trujillo.call_sessions SET operator_id=actor,state='accepted',accepted_at=now(),expires_at=now()+interval '30 minutes' WHERE id=p_id RETURNING * INTO c;
   UPDATE trujillo.help_requests SET stage='En revisión' WHERE id=p_id AND stage='Recibida';
   INSERT INTO trujillo.help_events(request_id,actor_id,stage,priority,reason)
   VALUES(p_id,actor,'En revisión',h.priority,'Operador aceptó la llamada. Conexión de audio pendiente.');
  ELSIF c.state<>'accepted' OR c.operator_id<>actor THEN
   RAISE EXCEPTION 'Llamada no disponible' USING ERRCODE='P0001';
  END IF;
 ELSIF p_action='end' THEN
  IF actor<>c.citizen_id AND actor IS DISTINCT FROM c.operator_id THEN
   RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501'; END IF;
  IF c.state IN ('waiting','accepted') THEN
   UPDATE trujillo.call_sessions SET state='ended',ended_at=now() WHERE id=p_id RETURNING * INTO c;
   INSERT INTO trujillo.help_events(request_id,actor_id,stage,priority,reason)
   VALUES(p_id,actor,h.stage,h.priority,'Llamada finalizada o cancelada. La solicitud de ayuda sigue disponible.');
  END IF;
 ELSIF p_action NOT IN ('start','status','token') THEN
  RAISE EXCEPTION 'Acción inválida' USING ERRCODE='22023';
 END IF;
 IF p_action='token' AND (c.state<>'accepted' OR (actor<>c.citizen_id AND actor IS DISTINCT FROM c.operator_id)) THEN
  RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501'; END IF;
 RETURN jsonb_build_object('id',c.id,'state',c.state,'expires_at',c.expires_at,
  'can_join',c.state='accepted' AND (actor=c.citizen_id OR actor=c.operator_id),
  'participant',actor::text);
END; $$;
REVOKE ALL ON FUNCTION trujillo.call_action(uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION trujillo.call_action(uuid,text) TO trujillo_api;
