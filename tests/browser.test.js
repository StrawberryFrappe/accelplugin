import { test } from 'node:test';
import assert from 'node:assert/strict';
import { detectBrowser, BROWSERS } from '../extension/lib/browser.js';

const ua = (s) => ({ userAgent: s });

test('detects Firefox from its runtime API', () => {
  assert.equal(detectBrowser({ runtime: { getBrowserInfo() {} } }, ua('Mozilla/5.0 Firefox/130.0')), 'firefox');
});

test('detects Brave', () => {
  assert.equal(detectBrowser({ runtime: {} }, { ...ua('Mozilla/5.0 Chrome/140.0'), brave: {} }), 'brave');
  assert.equal(detectBrowser({ runtime: {} }, { ...ua('Mozilla/5.0 Chrome/140.0'), userAgentData: { brands: [{ brand: 'Brave' }] } }), 'brave');
});

test('detects Opera GX', () => {
  assert.equal(detectBrowser({ runtime: {} }, ua('Mozilla/5.0 Chrome/151.0 Safari/537.36 OPR/136.0.0.0 (Edition GX)')), 'operagx');
  assert.equal(detectBrowser({ runtime: {} }, { ...ua('Mozilla/5.0'), userAgentData: { brands: [{ brand: 'Opera GX' }] } }), 'operagx');
});

test('falls back to Chrome', () => {
  assert.equal(detectBrowser({ runtime: {} }, ua('Mozilla/5.0 Chrome/140.0 Safari/537.36')), 'chrome');
  assert.equal(detectBrowser(undefined, undefined), 'chrome');
});

test('every browser has a name and a way to reach the setting', () => {
  for (const [id, b] of Object.entries(BROWSERS)) {
    assert.ok(b.name, id);
    assert.ok(b.settingsUrls.length || b.manualHint, id);
  }
});
