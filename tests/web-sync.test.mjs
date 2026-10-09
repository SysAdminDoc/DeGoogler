import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const inline = html.match(/<script>([\s\S]*?)<\/script>/)[1];

function createPage() {
  const storage = new Map();
  const queue = [];
  const messages = [];
  const listeners = [];
  const window = {
    addEventListener: (type, handler) => { if (type === 'message') listeners.push(handler); },
    postMessage: data => { messages.push(data); queue.push({ source: window, data }); }
  };
  const context = vm.createContext({
    window,
    location: { origin: 'https://sysadmindoc.github.io', protocol: 'https:' },
    navigator: {},
    localStorage: {
      getItem: key => storage.get(key) ?? null,
      setItem: (key, value) => storage.set(key, value)
    },
    document: { getElementById: () => null },
    setInterval: () => 1,
    fetch: () => new Promise(() => {})
  });
  vm.runInContext(inline + '\nrender = () => {}; renderSB = () => {};', context);
  return {
    storage,
    messages,
    run: code => vm.runInContext(code, context),
    receive: (data, source = window) => queue.push({ source, data }),
    flush() {
      let delivered = 0;
      while (queue.length && delivered < 50) {
        const event = queue.shift();
        for (const listener of listeners) listener(event);
        delivered++;
      }
      assert.equal(queue.length, 0, 'sync messages must settle instead of echoing indefinitely');
      return delivered;
    }
  };
}

test('publishing a plan does not re-import it into the web app', () => {
  const page = createPage();
  page.run('emitPlan()');
  assert.equal(page.flush(), 1);
  assert.equal(page.messages.length, 1);
  assert.equal(page.storage.size, 0);
});

test('legacy Browser Assistant plans persist without a reply loop', () => {
  const page = createPage();
  const services = [{ id: 'example', name: 'Example', type: 'email', steps: {} }];
  page.receive({ type: 'degoogler-plan-sync', plan: {
    actions: [{ id: 'install_tm', done: true }], connectedServices: services
  } });
  page.flush();
  assert.equal(JSON.parse(page.storage.get('dg-personal-chk')).install_tm, true);
  assert.deepEqual(JSON.parse(page.storage.get('dg-personal-tracker-services')), services);
  assert.equal(page.messages.length, 0);
});

test('local checklist edits still publish the current plan for the assistant', () => {
  const page = createPage();
  page.run('checks.install_tm = true; saveCk()');
  page.flush();
  assert.equal(page.messages.length, 1);
  const plan = page.messages[0].plan;
  assert.equal(page.messages[0].type, 'degoogler-plan-sync');
  assert.equal(plan.actions.find(action => action.id === 'install_tm').done, true);
});

test('assistant service imports publish one complete plan', () => {
  const page = createPage();
  const services = [{ id: 'example', name: 'Example', type: 'email', steps: {} }];
  page.receive({ type: 'degoogler-sync', services });
  page.flush();
  assert.equal(page.messages.length, 1);
  assert.deepEqual(JSON.parse(JSON.stringify(page.messages[0].plan.connectedServices)), services);
});

test('messages from another window cannot change migration progress', () => {
  const page = createPage();
  page.receive({ type: 'degoogler-plan-sync', plan: {
    actions: [{ id: 'install_tm', done: true }], connectedServices: []
  } }, {});
  page.flush();
  assert.equal(page.storage.size, 0);
  assert.equal(page.messages.length, 0);
});
