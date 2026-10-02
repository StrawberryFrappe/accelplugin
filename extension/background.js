import { matchDomain } from './lib/domains.js';
import { autoEnableStatus, sanitizeSettings } from './lib/policy.js';
import { getState, applyAndRestart, HelperError } from './lib/native.js';

const ALARM_TICK = 'tick';
const ALARM_WARN = 'autoEnableWarning';
const ALARM_REFRESH = 'refreshState';
const NOTIFICATION_ID = 'autoEnable';
// How long after a restart we still consider it "ours" (for the tab safety net).
const RESTART_WINDOW_MS = 5 * 60_000;
// If Opera is still running this long after we asked for a restart, assume it failed.
const RESTART_STUCK_MS = 2 * 60_000;

// chrome.storage.local keys:
//   settings             user settings (see lib/policy.js)
//   hw                   { enabled, pending, helper: 'ok'|'missing'|'error'|'unknown', error, checkedAt }
//   lastWatchedActiveAt  ms timestamp a watched site was last the active tab
//   postponedUntil       ms timestamp the auto re-enable was postponed to
//   warning              { at, deadline } while the "restarting soon" notification is up
//   restart              { target, at, reason, snapshot } while a restart we started is in flight
//   lastRestart          the same record, kept briefly after startup for the tab safety net
// chrome.storage.session keys (cleared when the browser restarts):
//   promptedTabs         { [tabId]: domain } tabs already prompted during this visit
//   snoozed              true after "Not now"

// ---------------------------------------------------------------- state helpers

// Tab, focus and alarm events arrive in bursts; run the state machine one call at a time
// so a burst can't trigger more than one restart.
let queue = Promise.resolve();
function serialized(fn) {
  return (...args) => {
    const run = queue.then(() => fn(...args));
    queue = run.catch(() => {});
    return run;
  };
}

async function loadSettings() {
  const { settings } = await chrome.storage.local.get('settings');
  return sanitizeSettings(settings);
}

async function loadHw() {
  const { hw } = await chrome.storage.local.get('hw');
  return hw || { enabled: null, pending: null, helper: 'unknown', error: null, checkedAt: 0 };
}

async function refreshHwState() {
  const prev = await loadHw();
  let hw;
  try {
    const s = await getState();
    hw = { enabled: s.running, pending: s.pending, helper: 'ok', error: null, checkedAt: Date.now() };
  } catch (e) {
    const helper = e instanceof HelperError ? e.code : 'error';
    hw = { ...prev, helper, error: e.message, checkedAt: Date.now() };
  }
  if (hw.enabled === false && prev.enabled !== false) {
    // Acceleration just turned off: start the inactivity clock now.
    await chrome.storage.local.set({ lastWatchedActiveAt: Date.now(), postponedUntil: 0 });
  }
  await chrome.storage.local.set({ hw });
  return hw;
}

async function activeWatchedTab(domains) {
  const tabs = await chrome.tabs.query({ active: true });
  return tabs.find((t) => matchDomain(t.url || t.pendingUrl, domains)) || null;
}

// ---------------------------------------------------------------- restart

async function snapshotTabs() {
  const windows = await chrome.windows.getAll({ populate: true, windowTypes: ['normal'] });
  return windows.map((w) => w.tabs.map((t) => t.url || t.pendingUrl).filter(isRestorableUrl));
}

function isRestorableUrl(url) {
  return typeof url === 'string' && /^(https?|file):/.test(url);
}

let restartInFlight = false;

async function restartWith(enabled, reason) {
  if (restartInFlight) return;
  restartInFlight = true;
  setTimeout(() => (restartInFlight = false), RESTART_STUCK_MS);
  await clearWarning();
  const snapshot = await snapshotTabs();
  await chrome.storage.local.set({ restart: { target: enabled, at: Date.now(), reason, snapshot } });
  try {
    await applyAndRestart(enabled);
  } catch (e) {
    restartInFlight = false;
    await chrome.storage.local.remove('restart');
    throw e;
  }
}

/** After a restart we triggered, reopen any tabs Opera's own session restore missed. */
async function restoreMissingTabs(restart) {
  const current = (await snapshotTabs()).flat();
  const counts = new Map();
  for (const url of current) counts.set(url, (counts.get(url) || 0) + 1);
  const missing = [];
  for (const url of restart.snapshot.flat()) {
    const n = counts.get(url) || 0;
    if (n > 0) counts.set(url, n - 1);
    else missing.push(url);
  }
  if (!missing.length) return;
  console.info('[accelplugin] reopening tabs missed by session restore:', missing);
  for (const url of missing) await chrome.tabs.create({ url, active: false });
}

// ---------------------------------------------------------------- auto re-enable

const evaluate = serialized(async () => {
  const settings = await loadSettings();
  const hw = await loadHw();
  const now = Date.now();
  const watched = await activeWatchedTab(settings.domains);
  if (watched) {
    await chrome.storage.local.set({ lastWatchedActiveAt: now });
    await clearWarning();
    return;
  }
  const { lastWatchedActiveAt, postponedUntil, warning, restart } = await chrome.storage.local.get([
    'lastWatchedActiveAt',
    'postponedUntil',
    'warning',
    'restart',
  ]);
  if (restart && now - restart.at > RESTART_STUCK_MS) {
    // The helper accepted the request but Opera never restarted; unblock.
    await chrome.storage.local.remove('restart');
  } else if (restart) return;
  if (warning || hw.helper !== 'ok') return;
  const status = autoEnableStatus({
    hwEnabled: hw.enabled,
    watchedActive: false,
    lastWatchedActiveAt: lastWatchedActiveAt || now,
    postponedUntil,
    now,
    settings,
  });
  if (!status.due) return;
  if (settings.warningSeconds > 0) await showWarning(settings.warningSeconds);
  else await doAutoRestart();
});

async function showWarning(seconds) {
  const deadline = Date.now() + seconds * 1000;
  await chrome.storage.local.set({ warning: { at: Date.now(), deadline } });
  await chrome.alarms.create(ALARM_WARN, { when: deadline });
  await chrome.notifications.create(NOTIFICATION_ID, {
    type: 'basic',
    iconUrl: 'icons/128.png',
    title: 'Turning hardware acceleration back on',
    message: `Opera GX will restart in ${seconds} seconds. Your tabs will be restored.`,
    buttons: [{ title: 'Restart now' }, { title: 'Postpone' }],
    requireInteraction: true,
    priority: 2,
  });
}

async function clearWarning() {
  const { warning } = await chrome.storage.local.get('warning');
  if (!warning) return;
  await chrome.storage.local.remove('warning');
  await chrome.alarms.clear(ALARM_WARN);
  await chrome.notifications.clear(NOTIFICATION_ID);
}

async function postpone() {
  const settings = await loadSettings();
  await clearWarning();
  await chrome.storage.local.set({ postponedUntil: Date.now() + settings.timeoutMinutes * 60_000 });
}

const autoRestart = serialized(() => doAutoRestart());

async function doAutoRestart() {
  // Re-check right before restarting: the user may have gone back to a watched site.
  const settings = await loadSettings();
  const hw = await loadHw();
  if (hw.enabled !== false || !settings.autoEnable) return clearWarning();
  if (await activeWatchedTab(settings.domains)) {
    await chrome.storage.local.set({ lastWatchedActiveAt: Date.now() });
    return clearWarning();
  }
  try {
    await restartWith(true, 'auto');
  } catch (e) {
    console.error('[accelplugin] auto re-enable failed:', e);
    await clearWarning();
    // Don't retry every minute on a persistent failure.
    await postpone();
  }
}

// ---------------------------------------------------------------- prompt banner

async function maybePrompt(tabId, url) {
  const settings = await loadSettings();
  const domain = matchDomain(url, settings.domains);
  const { promptedTabs = {}, snoozed } = await chrome.storage.session.get(['promptedTabs', 'snoozed']);

  if (!domain) {
    if (promptedTabs[tabId]) {
      delete promptedTabs[tabId];
      await chrome.storage.session.set({ promptedTabs });
    }
    return;
  }
  if (promptedTabs[tabId] === domain || snoozed) return;
  const hw = await loadHw();
  if (hw.enabled === false) return; // already off, nothing to ask

  promptedTabs[tabId] = domain;
  await chrome.storage.session.set({ promptedTabs });
  try {
    await chrome.scripting.executeScript({ target: { tabId }, files: ['content/banner.js'] });
  } catch (e) {
    console.warn(`[accelplugin] could not show banner on ${domain} (missing site permission?)`, e);
  }
}

async function forgetPromptIfLeft(tabId, url) {
  const settings = await loadSettings();
  if (matchDomain(url, settings.domains)) return;
  const { promptedTabs = {} } = await chrome.storage.session.get('promptedTabs');
  if (!promptedTabs[tabId]) return;
  delete promptedTabs[tabId];
  await chrome.storage.session.set({ promptedTabs });
}

async function openSetting() {
  // Opera accepts chrome:// as an alias of opera://.
  for (const url of ['opera://settings/?search=hardware%20acceleration', 'chrome://settings/?search=hardware%20acceleration']) {
    try {
      await chrome.tabs.create({ url });
      return;
    } catch {
      /* try next */
    }
  }
}

async function getStatus() {
  const settings = await loadSettings();
  const hw = await loadHw();
  const now = Date.now();
  const watched = await activeWatchedTab(settings.domains);
  const { lastWatchedActiveAt, postponedUntil, warning, restart } = await chrome.storage.local.get([
    'lastWatchedActiveAt',
    'postponedUntil',
    'warning',
    'restart',
  ]);
  const auto = autoEnableStatus({
    hwEnabled: hw.enabled,
    watchedActive: !!watched,
    lastWatchedActiveAt: lastWatchedActiveAt || now,
    postponedUntil,
    now,
    settings,
  });
  return { hw, settings, auto, warning: warning || null, restarting: !!restart, watchedDomain: watched ? matchDomain(watched.url || watched.pendingUrl, settings.domains) : null };
}

const handlers = {
  getStatus: () => getStatus(),
  refresh: async () => {
    await refreshHwState();
    return getStatus();
  },
  applyAndRestart: async ({ enabled }) => {
    await restartWith(!!enabled, 'user');
    return { ok: true };
  },
  testHelper: async () => {
    const res = await applyAndRestart(false, true);
    await refreshHwState();
    return res;
  },
  openSetting: async () => {
    await openSetting();
    return { ok: true };
  },
  snooze: async () => {
    await chrome.storage.session.set({ snoozed: true });
    return { ok: true };
  },
  postpone: async () => {
    await postpone();
    return { ok: true };
  },
};

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  const handler = handlers[msg?.type];
  if (!handler) return false;
  handler(msg)
    .then((result) => sendResponse({ ok: true, result }))
    .catch((e) => sendResponse({ ok: false, error: e?.message || String(e), code: e?.code }));
  return true; // async response
});

// ---------------------------------------------------------------- lifecycle

async function init(reason) {
  await chrome.alarms.create(ALARM_TICK, { periodInMinutes: 1 });
  const { restart } = await chrome.storage.local.get('restart');
  await chrome.storage.local.remove(['restart', 'warning']);
  if (reason === 'startup' && restart && Date.now() - restart.at < RESTART_WINDOW_MS) {
    // We just restarted ourselves: trust the target value until the helper confirms,
    // and keep the tab snapshot for the safety-net check below.
    const hw = await loadHw();
    await chrome.storage.local.set({
      hw: { ...hw, enabled: restart.target, pending: restart.target, checkedAt: Date.now() },
      lastWatchedActiveAt: Date.now(),
      postponedUntil: 0,
      lastRestart: restart,
    });
  } else {
    await refreshHwState();
  }
  // Local State is written lazily after startup, so check again shortly.
  await chrome.alarms.create(ALARM_REFRESH, { delayInMinutes: 0.5 });
}

chrome.runtime.onStartup.addListener(() => init('startup'));
chrome.runtime.onInstalled.addListener(async ({ reason }) => {
  if (reason === 'install') await chrome.storage.local.set({ settings: sanitizeSettings() });
  await init(reason);
});

chrome.alarms.onAlarm.addListener(async (alarm) => {
  if (alarm.name === ALARM_TICK) await evaluate();
  else if (alarm.name === ALARM_WARN) await autoRestart();
  else if (alarm.name === ALARM_REFRESH) {
    const { lastRestart } = await chrome.storage.local.get('lastRestart');
    if (lastRestart) {
      await chrome.storage.local.remove('lastRestart');
      if (Date.now() - lastRestart.at < RESTART_WINDOW_MS) await restoreMissingTabs(lastRestart);
    }
    await refreshHwState();
    await evaluate();
  }
});

chrome.notifications.onButtonClicked.addListener(async (id, index) => {
  if (id !== NOTIFICATION_ID) return;
  if (index === 0) await autoRestart();
  else await postpone();
});

chrome.tabs.onUpdated.addListener((tabId, info, tab) => {
  // Prompt once the page has loaded; a bare URL change only matters for leaving a watched site.
  if (info.status === 'complete') maybePrompt(tabId, tab.url).catch(console.error);
  else if (info.url) forgetPromptIfLeft(tabId, info.url).catch(console.error);
  if ((info.status === 'complete' || info.url) && tab.active) evaluate().catch(console.error);
});
chrome.tabs.onActivated.addListener(() => evaluate().catch(console.error));
chrome.windows.onFocusChanged.addListener(() => evaluate().catch(console.error));
chrome.tabs.onRemoved.addListener(async (tabId) => {
  const { promptedTabs = {} } = await chrome.storage.session.get('promptedTabs');
  if (promptedTabs[tabId]) {
    delete promptedTabs[tabId];
    await chrome.storage.session.set({ promptedTabs });
  }
});
