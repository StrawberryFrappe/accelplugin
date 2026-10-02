import { test } from 'node:test';
import assert from 'node:assert/strict';
import { autoEnableStatus, sanitizeSettings, DEFAULT_SETTINGS } from '../extension/lib/policy.js';

const MIN = 60_000;
const settings = sanitizeSettings({ timeoutMinutes: 15 });
const base = { hwEnabled: false, watchedActive: false, lastWatchedActiveAt: 0, postponedUntil: 0, now: 0, settings };

test('not eligible while hardware acceleration is on or unknown', () => {
  assert.equal(autoEnableStatus({ ...base, hwEnabled: true, now: 99 * MIN }).due, false);
  assert.equal(autoEnableStatus({ ...base, hwEnabled: null, now: 99 * MIN }).due, false);
});

test('not eligible when disabled in settings', () => {
  const s = sanitizeSettings({ autoEnable: false });
  assert.deepEqual(autoEnableStatus({ ...base, settings: s, now: 99 * MIN }).eligible, false);
});

test('never due while a watched site is active', () => {
  const r = autoEnableStatus({ ...base, watchedActive: true, now: 99 * MIN });
  assert.equal(r.due, false);
  assert.equal(r.reason, 'watched-site-active');
});

test('counts down from the last time a watched site was active', () => {
  const t0 = 1_000_000;
  let r = autoEnableStatus({ ...base, lastWatchedActiveAt: t0, now: t0 + 14 * MIN });
  assert.equal(r.due, false);
  assert.equal(r.remainingMs, MIN);
  r = autoEnableStatus({ ...base, lastWatchedActiveAt: t0, now: t0 + 15 * MIN });
  assert.equal(r.due, true);
  assert.equal(r.remainingMs, 0);
});

test('postpone pushes the deadline out', () => {
  const t0 = 1_000_000;
  const r = autoEnableStatus({ ...base, lastWatchedActiveAt: t0, postponedUntil: t0 + 30 * MIN, now: t0 + 20 * MIN });
  assert.equal(r.due, false);
  assert.equal(r.remainingMs, 10 * MIN);
});

test('sanitizeSettings fills defaults and clamps', () => {
  assert.deepEqual(sanitizeSettings(undefined), { ...DEFAULT_SETTINGS });
  const s = sanitizeSettings({ timeoutMinutes: '0', warningSeconds: -5, domains: 'x', autoEnable: 'yes' });
  assert.equal(s.timeoutMinutes, 1);
  assert.equal(s.warningSeconds, 0);
  assert.deepEqual(s.domains, DEFAULT_SETTINGS.domains);
  assert.equal(s.autoEnable, true);
});
