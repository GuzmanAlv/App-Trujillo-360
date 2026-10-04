CREATE SCHEMA trujillo;
REVOKE ALL ON SCHEMA trujillo FROM PUBLIC, anon, authenticated;
CREATE TABLE trujillo.schema_migrations (
    version integer PRIMARY KEY,
    applied_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE trujillo.users (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    auth_provider text NOT NULL CHECK (auth_provider IN ('firebase', 'supabase')),
    auth_subject text NOT NULL CHECK (length(trim(auth_subject)) BETWEEN 1 AND 256),
    display_name text NOT NULL CHECK (length(trim(display_name)) BETWEEN 1 AND 100),
    role text NOT NULL DEFAULT 'citizen' CHECK (role IN ('citizen','operator','admin')),
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','suspended')),
    suspension_reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (auth_provider, auth_subject),
    CHECK (status <> 'suspended' OR length(trim(suspension_reason)) > 0 AND suspension_reason IS NOT NULL)
);

CREATE TABLE trujillo.incidents (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    category text NOT NULL CHECK (category IN ('Robo','Auxilio','Agresión','Riesgo')),
    location extensions.geography(Point,4326) NOT NULL,
    occurred_at timestamptz NOT NULL,
    status text NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending','corroborated','verified','discarded','closed')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX incidents_location_idx ON trujillo.incidents USING gist(location);
CREATE INDEX incidents_match_idx ON trujillo.incidents(category, occurred_at)
    WHERE status IN ('pending','corroborated');

CREATE TABLE trujillo.reports (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES trujillo.users(id),
    incident_id uuid NOT NULL REFERENCES trujillo.incidents(id),
    request_id uuid NOT NULL,
    category text NOT NULL CHECK (category IN ('Robo','Auxilio','Agresión','Riesgo')),
    place text NOT NULL CHECK (length(trim(place)) BETWEEN 3 AND 100),
    description text NOT NULL DEFAULT '' CHECK (length(description) <= 500),
    location extensions.geography(Point,4326) NOT NULL,
    occurred_at timestamptz NOT NULL,
    received_at timestamptz NOT NULL DEFAULT now(),
    withdrawn_at timestamptz,
    UNIQUE(user_id, incident_id),
    UNIQUE(user_id, request_id)
);
CREATE INDEX reports_incident_idx ON trujillo.reports(incident_id);

CREATE TABLE trujillo.reviews (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    incident_id uuid NOT NULL REFERENCES trujillo.incidents(id),
    reviewer_id uuid NOT NULL REFERENCES trujillo.users(id),
    decision text NOT NULL CHECK (decision IN ('verified','discarded','closed','pending')),
    reason text NOT NULL CHECK (length(trim(reason)) BETWEEN 3 AND 1000),
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX reviews_incident_idx ON trujillo.reviews(incident_id, created_at);

CREATE FUNCTION trujillo.validate_review() RETURNS trigger
LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM trujillo.users WHERE id=NEW.reviewer_id
                   AND role IN ('operator','admin') AND status='active') THEN
        RAISE EXCEPTION 'Se requiere un operador activo' USING ERRCODE='23514';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER review_operator BEFORE INSERT ON trujillo.reviews
FOR EACH ROW EXECUTE FUNCTION trujillo.validate_review();

-- No Data API access. Runtime starts with health-only privileges until
-- authentication and transactional incident workflows are implemented.
ALTER TABLE trujillo.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE trujillo.incidents ENABLE ROW LEVEL SECURITY;
ALTER TABLE trujillo.reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE trujillo.reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE trujillo.schema_migrations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA trujillo FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA trujillo FROM PUBLIC, anon, authenticated;
INSERT INTO trujillo.schema_migrations(version) VALUES (1);
