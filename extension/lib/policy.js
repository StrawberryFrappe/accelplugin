// The auto re-enable decision. Pure so it can be unit-tested.
import { DEFAULT_DOMAINS } from './domains.js';

export const DEFAULT_SETTINGS = Object.freeze({
  domains: DEFAULT_DOMAINS,
  autoEnable: true,
  timeoutMinutes: 15,
  warningSeconds: 60,
});

/** Fill in missing/invalid settings with defaults. */
export function sanitizeSettings(raw) {
  const s = { ...DEFAULT_SETTINGS, ...(raw || {}) };
  if (!Array.isArray(s.domains)) s.domains = [...DEFAULT_DOMAINS];
  s.autoEnable = s.autoEnable !== false;
  s.timeoutMinutes = clampNumber(s.timeoutMinutes, 1, 24 * 60, DEFAULT_SETTINGS.timeoutMinutes);
  s.warningSeconds = clampNumber(s.warningSeconds, 0, 600, DEFAULT_SETTINGS.warningSeconds);
  return s;
}

function clampNumber(v, min, max, fallback) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.min(max, Math.max(min, Math.round(n)));
}

/**
 * Decide whether hardware acceleration should be switched back on.
 *
 * @param {object} p
 * @param {boolean|null} p.hwEnabled      running hardware-acceleration state (null = unknown)
 * @param {boolean} p.watchedActive        a watched site is the active tab in some window
 * @param {number} p.lastWatchedActiveAt  ms timestamp a watched site was last seen active
 * @param {number} [p.postponedUntil]     ms timestamp the user postponed the restart to
 * @param {number} p.now
 * @param {object} p.settings
 * @returns {{eligible: boolean, due: boolean, remainingMs: number|null, reason: string}}
 */
export function autoEnableStatus({ hwEnabled, watchedActive, lastWatchedActiveAt, postponedUntil = 0, now, settings }) {
  if (!settings.autoEnable) return { eligible: false, due: false, remainingMs: null, reason: 'disabled-in-settings' };
  if (hwEnabled !== false) return { eligible: false, due: false, remainingMs: null, reason: 'hw-accel-not-off' };
  const timeoutMs = settings.timeoutMinutes * 60_000;
  if (watchedActive) return { eligible: true, due: false, remainingMs: timeoutMs, reason: 'watched-site-active' };
  const deadline = Math.max((lastWatchedActiveAt || 0) + timeoutMs, postponedUntil || 0);
  const remainingMs = Math.max(0, deadline - now);
  return { eligible: true, due: remainingMs === 0, remainingMs, reason: remainingMs === 0 ? 'due' : 'counting-down' };
}
