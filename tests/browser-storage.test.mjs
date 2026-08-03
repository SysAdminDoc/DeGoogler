import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import vm from 'node:vm';
import { webcrypto } from 'node:crypto';

test('connected-service GM storage encrypts and round-trips', async () => {
  const source = await readFile(new URL('../DeGoogler-BrowserAssistant.user.js', import.meta.url), 'utf8');
  const start = source.indexOf('    // ── Connected-service storage ──');
  const end = source.indexOf('    // ── CSS ──', start);
  assert.ok(start >= 0 && end > start, 'storage helper section not found');

  const store = new Map();
  const context = {
    console,
    crypto: webcrypto,
    TextEncoder,
    TextDecoder,
    btoa: value => Buffer.from(value, 'binary').toString('base64'),
    atob: value => Buffer.from(value, 'base64').toString('binary'),
    GM_getValue: (key, fallback) => store.has(key) ? store.get(key) : fallback,
    GM_setValue: (key, value) => store.set(key, value)
  };
  vm.runInNewContext(source.slice(start, end) + '\nthis.api = { dgLoadServices, dgSaveServices };', context);

  const services = [{ id: 'svc-1', name: 'Example', type: 'email', priority: 'important', steps: { email: true } }];
  await context.api.dgSaveServices(services);
  const record = JSON.parse(store.get('dg-connected-services'));
  assert.equal(record.encryptedAtRest, true);
  assert.equal(record.algorithm, 'AES-GCM');
  assert.ok(record.data && !record.data.includes('Example'));
  assert.equal(JSON.stringify(await context.api.dgLoadServices()), JSON.stringify(services));
});
