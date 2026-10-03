import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';

const read = (p) => readFileSync(new URL(p, import.meta.url), 'utf8');

test('manifest key produces the extension ID the installer allows', () => {
  const manifest = JSON.parse(read('../extension/manifest.json'));
  const hex = createHash('sha256').update(Buffer.from(manifest.key, 'base64')).digest('hex').slice(0, 32);
  const id = [...hex].map((c) => String.fromCharCode(97 + parseInt(c, 16))).join('');
  const installer = read('../native-host/install.ps1');
  assert.match(installer, new RegExp(`\\$ExtensionId = '${id}'`));
});

test('host name matches between extension and helper', () => {
  const ext = read('../extension/lib/native.js').match(/HOST_NAME = '([^']+)'/)[1];
  const ps = read('../native-host/common.ps1').match(/AccelHostName = '([^']+)'/)[1];
  assert.equal(ext, ps);
});

test('Firefox add-on ID matches the helper and installer', () => {
  const manifest = JSON.parse(read('../extension/manifest.json'));
  const id = manifest.browser_specific_settings.gecko.id;
  assert.match(read('../native-host/install.ps1'), new RegExp(`\\$FirefoxExtensionId = '${id}'`));
  assert.match(read('../native-host/common.ps1'), new RegExp(`FirefoxExtensionId = '${id}'`));
});

test('manifest has a background entry for both engines', () => {
  const { background } = JSON.parse(read('../extension/manifest.json'));
  assert.equal(background.service_worker, 'background.js');
  assert.deepEqual(background.scripts, ['background.js']);
});

test('extension code uses the shared API namespace', () => {
  for (const f of ['background.js', 'lib/native.js', 'popup/popup.js', 'options/options.js']) {
    assert.doesNotMatch(read(`../extension/${f}`), /\bchrome\.(runtime|storage|tabs|windows|alarms|notifications|scripting|permissions)\b/, f);
  }
});
