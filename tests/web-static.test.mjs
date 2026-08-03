import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const html = fs.readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const inline = html.match(/<script>([\s\S]*?)<\/script>/)?.[1];

test('web app inline script and roadmap surfaces stay valid', () => {
  assert.ok(inline, 'index.html inline script is missing');
  new vm.Script(inline);
  for (const marker of ['mkDashboard', 'mkReverseMode', 'I18N', "value=\"es\"", "value=\"de\"", "value=\"fr\""]) {
    assert.match(html, new RegExp(marker.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')), `missing Web App marker: ${marker}`);
  }
});
