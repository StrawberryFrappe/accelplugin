import { DEFAULT_DOMAINS, normalizeDomain, originPatterns } from '../lib/domains.js';
import { sanitizeSettings } from '../lib/policy.js';

const $ = (id) => document.getElementById(id);
let settings;

async function send(type, extra = {}) {
  const res = await chrome.runtime.sendMessage({ type, ...extra });
  if (!res?.ok) throw new Error(res?.error || 'Extension did not respond.');
  return res.result;
}

async function save(patch) {
  settings = sanitizeSettings({ ...settings, ...patch });
  await chrome.storage.local.set({ settings });
  $('saved').hidden = false;
  clearTimeout(save.t);
  save.t = setTimeout(() => ($('saved').hidden = true), 1500);
}

function renderDomains() {
  const ul = $('domains');
  ul.replaceChildren();
  for (const d of settings.domains) {
    const li = document.createElement('li');
    const name = document.createElement('span');
    name.textContent = d;
    const rm = document.createElement('button');
    rm.className = 'ghost';
    rm.textContent = 'Remove';
    rm.addEventListener('click', () => removeDomain(d));
    li.append(name, rm);
    ul.append(li);
  }
  if (!settings.domains.length) {
    const li = document.createElement('li');
    li.className = 'muted';
    li.textContent = 'No sites. You will never be prompted.';
    ul.append(li);
  }
}

function domainError(text) {
  $('domainMsg').textContent = text;
  $('domainMsg').hidden = !text;
}

$('addForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  domainError('');
  const d = normalizeDomain($('newDomain').value);
  if (!d) return domainError('That doesn\'t look like a domain.');
  if (settings.domains.includes(d)) return domainError(`${d} is already listed.`);
  // Must run directly in the click handler: permission prompts need a user gesture.
  const granted = await chrome.permissions.request({ origins: originPatterns(d) });
  if (!granted) return domainError(`Permission for ${d} was not granted, so the prompt can't be shown there.`);
  $('newDomain').value = '';
  await save({ domains: [...settings.domains, d] });
  renderDomains();
});

async function removeDomain(d) {
  await save({ domains: settings.domains.filter((x) => x !== d) });
  renderDomains();
  // Built-in sites are required permissions and can't be removed.
  if (!DEFAULT_DOMAINS.includes(d)) await chrome.permissions.remove({ origins: originPatterns(d) }).catch(() => {});
}

$('autoEnable').addEventListener('change', (e) => save({ autoEnable: e.target.checked }));
$('timeoutMinutes').addEventListener('change', async (e) => {
  await save({ timeoutMinutes: e.target.value });
  e.target.value = settings.timeoutMinutes;
});
$('warningSeconds').addEventListener('change', async (e) => {
  await save({ warningSeconds: e.target.value });
  e.target.value = settings.warningSeconds;
});

function renderHelper(hw, detail) {
  const el = $('helperStatus');
  if (hw.helper === 'ok') {
    el.className = 'ok';
    el.textContent = `Installed. Hardware acceleration is ${hw.enabled === false ? 'off' : 'on'}.`;
  } else {
    el.className = 'err';
    el.textContent = hw.error || 'Not checked yet.';
  }
  $('helperDetails').hidden = !detail;
  $('helperDetails').textContent = detail || '';
}

$('test').addEventListener('click', async () => {
  $('test').disabled = true;
  try {
    const res = await send('testHelper');
    const status = await send('getStatus');
    const { ok, dryRun, ...info } = res;
    renderHelper(status.hw, `Dry run OK (nothing was restarted):\n${JSON.stringify(info, null, 2)}`);
  } catch (e) {
    const status = await send('getStatus').catch(() => null);
    renderHelper(status?.hw || { helper: 'error' }, e.message);
  } finally {
    $('test').disabled = false;
  }
});

async function init() {
  const stored = await chrome.storage.local.get('settings');
  settings = sanitizeSettings(stored.settings);
  renderDomains();
  $('autoEnable').checked = settings.autoEnable;
  $('timeoutMinutes').value = settings.timeoutMinutes;
  $('warningSeconds').value = settings.warningSeconds;
  $('extId').textContent = chrome.runtime.id;
  const status = await send('refresh').catch(() => null);
  if (status) renderHelper(status.hw);
}

init();
