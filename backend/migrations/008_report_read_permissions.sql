-- Owner reads use PostGIS coordinates; table RLS remains unchanged.
GRANT USAGE ON SCHEMA extensions TO trujillo_api;
INSERT INTO trujillo.schema_migrations(version) VALUES(8);
