/**
 * Run AI simulation SQL against an isolated, in-memory PostgreSQL (PGlite).
 * No Supabase credentials or network/database mutations are used.
 *
 * Install outside the repository:
 *   npm install --prefix <temporary-folder> @electric-sql/pglite@0.6.0
 * Run:
 *   node backend/verify_ai_simulation.mjs <temporary-folder>/node_modules/@electric-sql/pglite/dist/index.js
 */
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { randomUUID, createHash } from 'node:crypto';

const backend = dirname(fileURLToPath(import.meta.url));
const modulePath = process.argv[2];
if (!modulePath) throw new Error('Pass the absolute path to the PGlite module as argument.');
const { PGlite } = await import(pathToFileURL(resolve(modulePath)).href);
const db = new PGlite();
let assertions = 0;

async function scalar(query, params = []) {
  const { rows } = await db.query(query, params);
  return rows.length ? Object.values(rows[0])[0] : null;
}

async function asActor(uid) {
  await db.exec('RESET ROLE');
  await db.query("SELECT set_config('app.firebase_uid',$1,false)", [uid]);
  await db.exec('SET ROLE trujillo_api');
}

async function admin(query, params = []) {
  await db.exec('RESET ROLE');
  return db.query(query, params);
}

async function rejectsSql(query, params = [], expectedCode = '42501') {
  await assert.rejects(() => db.query(query, params), error => {
    assert.equal(error.code, expectedCode, error.message);
    return true;
  });
  assertions++;
}

async function prepare() {
  await db.exec(`
    CREATE ROLE anon;
    CREATE ROLE authenticated;
    CREATE ROLE trujillo_api;
    CREATE SCHEMA trujillo;
    GRANT USAGE ON SCHEMA trujillo TO trujillo_api;
    CREATE TABLE trujillo.users(
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      auth_provider text NOT NULL DEFAULT 'firebase',
      auth_subject text NOT NULL UNIQUE,
      display_name text NOT NULL DEFAULT 'SQL verification',
      auth_email text,
      role text NOT NULL DEFAULT 'citizen',
      status text NOT NULL DEFAULT 'active'
    );
  `);
  const workflowSql = await readFile(resolve(backend, 'migrations/012_workflows.sql'), 'utf8');
  const actorFunction = workflowSql.match(/CREATE FUNCTION trujillo\.current_actor\([\s\S]*?END; \$\$;/)?.[0];
  assert.ok(actorFunction, 'Extract current_actor from the existing migration');
  await db.exec(actorFunction);
  await db.exec(await readFile(resolve(backend, 'migrations/017_ai_candidates.sql'), 'utf8'));
  await db.exec(await readFile(resolve(backend, 'supabase/migrations/20261125193721_ai_camera_simulation.sql'), 'utf8'));
}

try {
  await prepare();
  const uid = { owner: randomUUID(), other: randomUUID(), citizen: randomUUID() };
  const userIds = {};
  for (const [kind, subject] of Object.entries(uid)) {
    const result = await admin(`INSERT INTO trujillo.users(auth_subject,auth_email,role,display_name)
      VALUES($1,$2,$3,$4) RETURNING id`, [subject, `${kind}@example.test`, kind === 'citizen' ? 'citizen' : 'operator', kind]);
    userIds[kind] = result.rows[0].id;
  }
  await admin("INSERT INTO trujillo.ai_cameras(id) VALUES('test-phone-camera')");
  await admin("INSERT INTO trujillo.sim_camera_permissions(email,camera_id) VALUES('owner@example.test','test-phone-camera')");
  const tokenHash = createHash('sha256').update('verification-only-worker-token').digest('hex');
  const createSessionQuery = "SELECT trujillo.create_sim_session('test-phone-camera',-8.11,-79.02,$1)";
  const eventQuery = 'SELECT trujillo.receive_sim_event($1,$2,$3,$4,$5)';
  async function event(session, confidence, requestId = randomUUID(), model = 'test-r2plus1d') {
    return scalar(eventQuery, [session, tokenHash, requestId, confidence, model]);
  }

  await asActor(uid.citizen);
  await rejectsSql('SELECT trujillo.simulation_config()');
  await rejectsSql('SELECT * FROM trujillo.sim_cases()');
  await rejectsSql(createSessionQuery, [tokenHash]);
  await asActor(uid.other);
  assert.equal((await scalar('SELECT trujillo.simulation_config()')).enabled, false); assertions++;
  await rejectsSql(createSessionQuery, [tokenHash]);

  await asActor(uid.owner);
  assert.deepEqual(await scalar('SELECT trujillo.simulation_config()'), {
    enabled: true, cameraId: 'test-phone-camera', threshold: .85,
  }); assertions++;
  for (const table of ['sim_camera_permissions', 'sim_sessions', 'sim_cases', 'sim_case_events', 'sim_received_windows']) {
    await rejectsSql(`SELECT * FROM trujillo.${table}`);
  }
  const session = await scalar(createSessionQuery, [tokenHash]);
  assert.equal(typeof session.id, 'string');
  assert.ok(new Date(session.expiresAt) > new Date()); assertions++;
  await rejectsSql(eventQuery, [session.id, '0'.repeat(64), randomUUID(), .99, 'test'], '28000');
  await rejectsSql(eventQuery, [randomUUID(), tokenHash, randomUUID(), .99, 'test'], '28000');
  await rejectsSql(eventQuery, [session.id, tokenHash, randomUUID(), 1.01, 'test'], '22023');

  const request1 = randomUUID();
  assert.equal((await event(session.id, .9, request1)).status, 'warming_up'); assertions++;
  assert.equal((await event(session.id, .9, request1)).status, 'warming_up'); assertions++;
  await rejectsSql(eventQuery, [session.id, tokenHash, request1, .91, 'test-r2plus1d'], 'P0001');
  // Replaying a high window must not increment the consecutive-window counter.
  assert.equal((await event(session.id, .3)).status, 'below_threshold'); assertions++;
  assert.equal((await event(session.id, .9)).status, 'warming_up'); assertions++;
  // A stale high window must not combine with a new high window after a pause.
  await admin("UPDATE trujillo.sim_sessions SET last_observed_at=clock_timestamp()-interval '11 seconds' WHERE id=$1", [session.id]);
  await asActor(uid.owner);
  assert.equal((await event(session.id, .91)).status, 'warming_up'); assertions++;
  const creationRequest = randomUUID();
  const created = await event(session.id, .95, creationRequest);
  assert.equal(created.status, 'created');
  assert.equal(created.case.simulation, true);
  assert.equal(created.case.stage, 'Recibida');
  assert.equal(created.case.latitude, -8.11);
  assert.equal(created.case.longitude, -79.02);
  assert.equal(created.case.events.length, 1); assertions++;
  assert.deepEqual(await event(session.id, .95, creationRequest), created); assertions++;
  assert.equal((await event(session.id, .99)).status, 'cooldown'); assertions++;
  assert.equal((await db.query('SELECT * FROM trujillo.sim_cases()')).rows.length, 1); assertions++;

  await asActor(uid.other);
  assert.equal((await db.query('SELECT * FROM trujillo.sim_cases()')).rows.length, 1); assertions++;
  await rejectsSql('SELECT trujillo.stop_sim_session($1)', [session.id], 'P0002');
  await rejectsSql('SELECT trujillo.review_sim_case($1,$2,$3)', [created.case.id, 'Cerrada', 'No permite saltar revisión'], '22023');
  const decisionQuery = 'SELECT trujillo.review_sim_case($1,$2,$3)';
  const review = await scalar(decisionQuery, [created.case.id, 'En revisión', 'Operador revisa la simulación']);
  assert.equal(review.stage, 'En revisión');
  assert.equal(review.events.at(-1).actor, 'other');
  assert.ok(review.events.at(-1).at); assertions++;
  assert.deepEqual(await scalar(decisionQuery, [created.case.id, 'En revisión', 'Operador revisa la simulación']), review); assertions++;
  const action = await scalar(decisionQuery, [created.case.id, 'Acción registrada', 'Atención simulada registrada']);
  assert.equal(action.events.length, 3); assertions++;
  const closed = await scalar(decisionQuery, [created.case.id, 'Cerrada', 'Simulación atendida y finalizada']);
  assert.equal(closed.events.length, 4);
  assert.equal(closed.stage, 'Cerrada'); assertions++;
  await rejectsSql(decisionQuery, [created.case.id, 'En revisión', 'No permite reabrir simulación'], '22023');
  await asActor(uid.citizen);
  await rejectsSql(decisionQuery, [created.case.id, 'En revisión', 'Un ciudadano no puede atender']);

  // A later detection should create a separate case, after cooldown elapsed.
  await admin("UPDATE trujillo.sim_cases SET received_at=clock_timestamp()-interval '61 seconds' WHERE id=$1", [created.case.id]);
  await asActor(uid.owner);
  assert.equal((await event(session.id, .99)).status, 'warming_up'); assertions++;
  const later = await event(session.id, .99);
  assert.equal(later.status, 'created');
  assert.notEqual(later.case.id, created.case.id); assertions++;
  const discarded = await scalar(decisionQuery, [later.case.id, 'Descartada', 'Falsa alarma de la simulación']);
  assert.equal(discarded.stage, 'Descartada'); assertions++;

  await admin("UPDATE trujillo.sim_camera_permissions SET enabled=false WHERE email='owner@example.test'");
  await asActor(uid.owner);
  assert.equal((await scalar('SELECT trujillo.simulation_config()')).enabled, false); assertions++;
  await rejectsSql(eventQuery, [session.id, tokenHash, randomUUID(), .99, 'test']);
  await admin("UPDATE trujillo.sim_camera_permissions SET enabled=true WHERE email='owner@example.test'");
  await admin("UPDATE trujillo.users SET status='suspended' WHERE id=$1", [userIds.owner]);
  await asActor(uid.owner);
  await rejectsSql(eventQuery, [session.id, tokenHash, randomUUID(), .99, 'test']);
  await rejectsSql('SELECT trujillo.simulation_config()');
  await admin("UPDATE trujillo.users SET status='active' WHERE id=$1", [userIds.owner]);
  await admin("UPDATE trujillo.ai_cameras SET active=false WHERE id='test-phone-camera'");
  await asActor(uid.owner);
  await rejectsSql(eventQuery, [session.id, tokenHash, randomUUID(), .99, 'test']);
  await admin("UPDATE trujillo.ai_cameras SET active=true WHERE id='test-phone-camera'");
  await asActor(uid.owner);
  assert.equal((await scalar('SELECT trujillo.stop_sim_session($1)', [session.id])).status, 'stopped'); assertions++;
  await rejectsSql(eventQuery, [session.id, tokenHash, randomUUID(), .99, 'test'], 'P0001');

  const old = await scalar(createSessionQuery, [tokenHash]);
  const replacement = await scalar(createSessionQuery, [tokenHash]);
  await rejectsSql(eventQuery, [old.id, tokenHash, randomUUID(), .99, 'test'], 'P0001');
  await admin("UPDATE trujillo.sim_sessions SET expires_at=clock_timestamp()-interval '1 second' WHERE id=$1", [replacement.id]);
  await asActor(uid.owner);
  await rejectsSql(eventQuery, [replacement.id, tokenHash, randomUUID(), .99, 'test'], 'P0001');

  const tableSecurity = await admin(`SELECT count(*)::int AS count,
      bool_and(c.relrowsecurity) AS all_rls
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='trujillo' AND c.relkind='r' AND c.relname LIKE 'sim_%'`);
  assert.equal(tableSecurity.rows[0].count, 5);
  assert.equal(tableSecurity.rows[0].all_rls, true); assertions++;
  const functionSecurity = await admin(`SELECT p.proname,
      COALESCE(array_to_string(p.proconfig,','),'') AS config,
      has_function_privilege('anon',p.oid,'EXECUTE') AS anon_exec,
      has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated_exec
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='trujillo' AND p.proname IN
      ('simulation_config','create_sim_session','stop_sim_session','sim_case_json',
       'receive_sim_event','sim_cases','review_sim_case')`);
  assert.equal(functionSecurity.rows.length, 7);
  for (const row of functionSecurity.rows) {
    assert.ok(row.config.includes('search_path=""'), `${row.proname}: empty search_path`);
    assert.equal(row.anon_exec, false, `${row.proname}: no anonymous execution`);
    assert.equal(row.authenticated_exec, false, `${row.proname}: no Data API execution`);
    assertions++;
  }
  // Give test roles schema access deliberately, to prove the function's own ACL
  // blocks invocation even if schema visibility changes later.
  await admin('GRANT USAGE ON SCHEMA trujillo TO anon,authenticated');
  for (const role of ['anon', 'authenticated']) {
    await db.exec(`SET ROLE ${role}`);
    await rejectsSql('SELECT trujillo.simulation_config()');
    await rejectsSql('SELECT * FROM trujillo.sim_cases()');
    await rejectsSql(eventQuery, [replacement.id, tokenHash, randomUUID(), .99, 'test']);
    await db.exec('RESET ROLE');
  }
  console.log(`Verified ${assertions} AI simulation checks against isolated PostgreSQL; no remote writes.`);
} finally {
  await db.close();
}
