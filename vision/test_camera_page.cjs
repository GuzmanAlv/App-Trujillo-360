// Verify session handoff and pairing reload without hardware or real credentials.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const html = fs.readFileSync(__dirname + '/simulation_camera.html', 'utf8');
const code = html.match(/<script>([\s\S]*?)<\/script>/)[1];

async function check() {
  const elements = new Map();
  function element(selector) {
    if (!elements.has(selector)) elements.set(selector, {
      textContent: '', value: '', hidden: true, disabled: false,
      getContext: () => ({}), srcObject: null,
    });
    return elements.get(selector);
  }
  const storage = new Map();
  const calls = [];
  const context = {
    document: { querySelector: element, addEventListener() {} },
    window: { addEventListener() {} }, navigator: {},
    location: { hash: '#pair=local-test', pathname: '/' },
    history: { replaceState() {} },
    sessionStorage: { getItem: key => storage.get(key), setItem: (key, value) => storage.set(key, value) },
    URLSearchParams, AbortController, setTimeout, clearTimeout,
    atob: text => Buffer.from(text, 'base64').toString('binary'),
    fetch: async (url, options = {}) => {
      calls.push({ url, options });
      return { ok: true, json: async () => options.method === 'POST'
        ? { sessionReady: true, binding: 'local-binding' } : { needsAccess: true, sessionReady: false } };
    },
  };
  vm.runInNewContext(code, context);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(storage.get('trujillo-camera-pair'), 'local-test');
  assert.equal(element('#access-panel').hidden, false);
  assert.equal(element('#start').disabled, true);
  const access = { schemaVersion: 1, id: 'test-session', workerToken: 'test-only-secret', expiresAt: '2026-11-25T00:00:00Z' };
  element('#camera-access').value = 'TRUJILLO-CAMERA-1.' + Buffer.from(JSON.stringify(access)).toString('base64url');
  await element('#connect').onclick();
  const post = calls.find(call => call.options.method === 'POST');
  assert.deepEqual(JSON.parse(post.options.body), access);
  assert.equal(post.options.headers['X-Pairing-Token'], 'local-test');
  assert.equal(element('#camera-access').value, '');
  assert.equal(storage.get('trujillo-camera-binding'), 'local-binding');
  assert.match(element('#session-status').textContent, /Sesión conectada/);
  assert.equal(element('#start').disabled, false);
  assert.equal(element('#session-status').textContent.includes(access.workerToken), false);
  // A malformed code cannot reach the service.
  const before = calls.length;
  element('#camera-access').value = 'not-a-camera-code';
  await element('#connect').onclick();
  assert.equal(calls.length, before);
  // Refreshing this tab recovers only its local pairing, never worker credentials.
  context.location.hash = '';
  vm.runInNewContext(code, { ...context });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(calls.at(-1).options.headers['X-Pairing-Token'], 'local-test');
  assert.equal(calls.at(-1).options.headers['X-Camera-Binding'], 'local-binding');
  console.log('Phone page: activation handoff, invalid code, secret clearing and reload verified.');
}
check().catch(error => { console.error(error); process.exitCode = 1; });
