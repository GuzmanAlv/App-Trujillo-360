GRANT SELECT ON trujillo.users TO trujillo_api;
GRANT INSERT (auth_provider, auth_subject, display_name) ON trujillo.users TO trujillo_api;
CREATE POLICY identity_read ON trujillo.users FOR SELECT TO trujillo_api
USING (auth_provider = 'firebase' AND auth_subject = current_setting('app.firebase_uid', true));
CREATE POLICY identity_insert ON trujillo.users FOR INSERT TO trujillo_api
WITH CHECK (auth_provider = 'firebase' AND auth_subject = current_setting('app.firebase_uid', true)
    AND role = 'citizen' AND status = 'active');
INSERT INTO trujillo.schema_migrations(version) VALUES (2);
