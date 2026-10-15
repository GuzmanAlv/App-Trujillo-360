-- DATOS FICTICIOS PARA PRESENTACION. No representan denuncias reales.
-- Ejecutar completo en Supabase SQL Editor, con el rol postgres.
-- 15 incidentes, 3 usuarios ficticios internos, 45 aportes; sin fotos.
-- No crea usuarios en Firebase ni permite iniciar sesion con ellos.
-- Las ubicaciones son aproximadas, repartidas por Trujillo y alrededores.
-- Repetir este archivo no duplica datos; actualiza las fechas de esta misma demo.
-- Si una cuenta real aporto a un grupo de demo, se aborta para no modificarlo.
BEGIN;
SELECT pg_advisory_xact_lock(360015);
DO $$
DECLARE
  d record;
  n integer;
  demo_users uuid[];
  user_key uuid;
  incident_key uuid;
  report_key uuid;
  subject_key text;
  event_time timestamptz;
BEGIN
  IF coalesce((SELECT max(version) FROM trujillo.schema_migrations),0) < 11 THEN
    RAISE EXCEPTION 'Se requiere el esquema 11 o posterior. No se crearon datos.';
  END IF;
  FOR n IN 1..3 LOOP
    user_key := md5('trujillo360:demo:20261014:user:' || n)::uuid;
    subject_key := 'demo-presentacion-20261014-' || n;
    IF EXISTS (SELECT 1 FROM trujillo.users u WHERE u.id=user_key
      AND (u.auth_provider<>'supabase' OR u.auth_subject<>subject_key)) THEN
      RAISE EXCEPTION 'Identificador ocupado; no se modificaron usuarios reales.';
    END IF;
    INSERT INTO trujillo.users(id,auth_provider,auth_subject,display_name)
    VALUES(user_key,'supabase',subject_key,'DEMO - Participante ficticio ' || n)
    ON CONFLICT(id) DO NOTHING;
    demo_users := array_append(demo_users,user_key);
  END LOOP;

  FOR d IN SELECT * FROM (VALUES
    (1, 'Centro historico - zona norte', 'Robo',     -8.1078, -79.0305),
    (2, 'Centro historico - zona sur',   'Auxilio',  -8.1160, -79.0270),
    (3, 'El Molino - zona oeste',        'Robo',     -8.1038, -79.0250),
    (4, 'El Molino - zona este',         'Agresión', -8.1025, -79.0208),
    (5, 'La Esperanza - zona sur',       'Agresión', -8.0800, -79.0430),
    (6, 'La Esperanza - zona norte',     'Riesgo',   -8.0675, -79.0500),
    (7, 'El Porvenir - zona oeste',      'Robo',     -8.0830, -79.0080),
    (8, 'El Porvenir - zona este',       'Auxilio',  -8.0775, -78.9995),
    (9, 'Florencia de Mora',             'Agresión', -8.0875, -79.0235),
    (10,'La Noria',                      'Riesgo',   -8.1065, -79.0115),
    (11,'California',                    'Robo',     -8.1290, -79.0410),
    (12,'San Andres',                    'Auxilio',  -8.1185, -79.0380),
    (13,'Victor Larco - Buenos Aires',   'Robo',     -8.1430, -79.0520),
    (14,'Victor Larco - zona interior',  'Riesgo',   -8.1360, -79.0450),
    (15,'Huanchaco',                     'Auxilio',  -8.0790, -79.1200)
  ) AS example(number,zone,category,lat,lng) LOOP
    incident_key := md5('trujillo360:demo:20261014:incident:' || d.number)::uuid;
    IF EXISTS (SELECT 1 FROM trujillo.reports r WHERE r.incident_id=incident_key
      AND (NOT (r.user_id=ANY(demo_users)) OR r.description<>
      'DEMOSTRACION: incidente ficticio para una presentacion. No es una denuncia real.')) THEN
      RAISE EXCEPTION 'El grupo de demo tiene otros aportes. No se modificaron datos.';
    END IF;
    event_time := now() - interval '90 minutes' + d.number * interval '3 minutes';
    INSERT INTO trujillo.incidents(id,category,location,occurred_at)
    VALUES(incident_key,d.category,
      extensions.ST_SetSRID(extensions.ST_MakePoint(d.lng,d.lat),4326)::extensions.geography,event_time)
    ON CONFLICT(id) DO UPDATE SET occurred_at=EXCLUDED.occurred_at,
      updated_at=now();

    FOR n IN 1..3 LOOP
      report_key := md5('trujillo360:demo:20261014:report:' || d.number || ':' || n)::uuid;
      INSERT INTO trujillo.reports(id,user_id,incident_id,request_id,category,place,
        description,location,occurred_at)
      VALUES(report_key,demo_users[n],incident_key,report_key,d.category,
        'DEMO - ' || d.zone,
        'DEMOSTRACION: incidente ficticio para una presentacion. No es una denuncia real.',
        extensions.ST_SetSRID(extensions.ST_MakePoint(
          d.lng+(n-2)*0.00008,d.lat+(n-2)*0.00008),4326)::extensions.geography,
        event_time+(n-1)*interval '2 minutes')
      ON CONFLICT(id) DO UPDATE SET occurred_at=EXCLUDED.occurred_at;
    END LOOP;

    UPDATE trujillo.incidents i SET
      corroboration_count=(SELECT count(DISTINCT r.user_id) FROM trujillo.reports r
        WHERE r.incident_id=i.id AND r.withdrawn_at IS NULL),
      status='corroborated',needs_review=false,updated_at=now()
    WHERE i.id=incident_key;
    IF (SELECT corroboration_count FROM trujillo.incidents WHERE id=incident_key) <> 3 THEN
      RAISE EXCEPTION 'La demo debe tener exactamente tres cuentas por incidente.';
    END IF;
  END LOOP;
END;
$$;

WITH demo_ids AS (
  SELECT md5('trujillo360:demo:20261014:incident:' || n)::uuid AS id
  FROM generate_series(1,15) AS sequence(n)
)
SELECT count(DISTINCT i.id) AS incidentes_demo,
       count(r.id) AS reportes_demo,
       count(DISTINCT i.id) FILTER (
         WHERE i.status='corroborated' AND i.corroboration_count=3
       ) AS grupos_corroborados
FROM demo_ids d
JOIN trujillo.incidents i ON i.id=d.id
LEFT JOIN trujillo.reports r ON r.incident_id=i.id;
COMMIT;
