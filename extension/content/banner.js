// Injected by background.js into watched sites when hardware acceleration is on.
//
// Streaming sites are hostile to injected UI: they lay invisible overlays over the page,
// swallow clicks in capture-phase listeners, and disable pointer events with !important
// rules. So the banner:
//   - lives in the browser's top layer (popover), above any z-index the page uses,
//   - pins its own host styles with !important inline declarations,
//   - handles clicks itself from a window capture listener, which still runs when the
//     page stops propagation, and draws its own switch instead of relying on a checkbox
//     whose toggle the page could cancel.
(() => {
  if (window.__accelpluginBanner) {
    window.__accelpluginBanner.show();
    return;
  }

  const send = (type, extra = {}) =>
    chrome.runtime.sendMessage({ type, ...extra }).then((res) => {
      if (!res?.ok) throw new Error(res?.error || 'Extension did not respond.');
      return res.result;
    });

  const host = document.createElement('accelplugin-banner');
  const HOST_STYLE = {
    display: 'block', position: 'fixed', top: '16px', right: '16px', bottom: 'auto', left: 'auto',
    margin: '0', padding: '0', border: '0', background: 'transparent', overflow: 'visible',
    width: 'auto', height: 'auto', 'max-width': 'none', 'max-height': 'none',
    'z-index': '2147483647', 'pointer-events': 'auto', opacity: '1', visibility: 'visible',
    transform: 'none', filter: 'none', 'clip-path': 'none', 'color-scheme': 'dark',
  };
  for (const [prop, value] of Object.entries(HOST_STYLE)) host.style.setProperty(prop, value, 'important');
  host.setAttribute('popover', 'manual');

  const root = host.attachShadow({ mode: 'closed' });
  root.innerHTML = `
    <style>
      * { pointer-events: auto; box-sizing: border-box; }
      .card {
        width: 360px; max-width: calc(100vw - 32px); padding: 16px 18px 14px;
        font: 13px/1.45 system-ui, -apple-system, "Segoe UI", sans-serif; color: #ececf1;
        background: #17161d; border: 1px solid #2c2a36; border-left: 3px solid #fa1e4e;
        border-radius: 10px; box-shadow: 0 12px 32px rgba(0, 0, 0, .45);
        animation: in .18s ease-out; text-align: left;
      }
      @keyframes in { from { opacity: 0; transform: translateY(-6px); } }
      .head { display: flex; align-items: start; gap: 8px; }
      h1 { flex: 1; margin: 0 0 4px; font-size: 14px; font-weight: 600; color: #ececf1; }
      p { margin: 0 0 12px; color: #a9a7b6; }
      button { all: unset; cursor: pointer; }
      button:focus-visible { outline: 2px solid #fa1e4e; outline-offset: 2px; }
      .x { color: #77758a; font-size: 18px; line-height: 1; padding: 0 2px; }
      .x:hover { color: #ececf1; }
      .setting {
        display: flex; align-items: center; justify-content: space-between; gap: 10px; cursor: pointer;
        padding: 10px 12px; margin-bottom: 12px; background: #201f28; border-radius: 8px;
      }
      .setting small { display: block; color: #8a8898; font-size: 11px; }
      .switch { position: relative; width: 38px; height: 22px; flex: none; border-radius: 11px; background: #3a3846; transition: background .15s; }
      .switch::after {
        content: ''; position: absolute; top: 3px; left: 3px; width: 16px; height: 16px;
        border-radius: 50%; background: #fff; transition: transform .15s;
      }
      .switch[aria-checked="true"] { background: #fa1e4e; }
      .switch[aria-checked="true"]::after { transform: translateX(16px); }
      .actions { display: flex; gap: 8px; align-items: center; }
      .primary, .ghost { padding: 7px 12px; border-radius: 6px; font-weight: 600; font-size: 12.5px; white-space: nowrap; }
      .primary { background: #fa1e4e; color: #fff; }
      .primary:hover { background: #ff3b66; }
      .ghost { color: #a9a7b6; }
      .ghost:hover { color: #ececf1; background: #24232c; }
      .link { margin-left: auto; white-space: nowrap; color: #8a8898; font-size: 11.5px; text-decoration: underline; }
      .link:hover { color: #ececf1; }
      [aria-disabled="true"] { opacity: .45; cursor: default; }
      .msg { margin: 10px 0 0; font-size: 12px; color: #a9a7b6; }
      .msg.err { color: #ff8197; }
      [hidden] { display: none !important; }
    </style>
    <div class="card" role="dialog" aria-label="Hardware acceleration">
      <div class="head">
        <h1>Turn off hardware acceleration?</h1>
        <button class="x" data-act="close" title="Close" aria-label="Close">×</button>
      </div>
      <p class="intro">This site is on your list. Switch the setting off, then restart Opera GX to apply it.</p>
      <div class="setting" data-act="toggle">
        <span>Use hardware acceleration when available<small class="state">Checking…</small></span>
        <button class="switch" role="switch" aria-checked="true" aria-disabled="true" data-act="toggle"
          aria-label="Use hardware acceleration when available"></button>
      </div>
      <div class="actions">
        <button class="primary" data-act="restart" aria-disabled="true">Restart browser</button>
        <button class="ghost" data-act="snooze">Not now</button>
        <button class="link" data-act="setting">Open setting</button>
      </div>
      <div class="msg" hidden></div>
    </div>`;

  const $ = (sel) => root.querySelector(sel);
  const toggle = $('.switch');
  const restartBtn = $('[data-act="restart"]');
  const stateEl = $('.state');
  const msgEl = $('.msg');
  let current = null; // running state reported by the helper
  let wanted = true; // what the switch shows
  let busy = true; // switch and restart are inactive until status loads

  function setBusy(value) {
    busy = value;
    toggle.setAttribute('aria-disabled', String(value));
    restartBtn.setAttribute('aria-disabled', String(value));
  }

  function setWanted(value) {
    wanted = value;
    toggle.setAttribute('aria-checked', String(value));
    if (current === null) return;
    restartBtn.textContent = wanted !== current ? (wanted ? 'Turn on & restart' : 'Turn off & restart') : 'Restart browser';
  }

  function showMsg(text, isError = false) {
    msgEl.textContent = text;
    msgEl.classList.toggle('err', isError);
    msgEl.hidden = !text;
  }

  function remove() {
    window.removeEventListener('click', onClick, true);
    host.remove();
  }

  /** Put the banner in the top layer, above anything the page has drawn. */
  function raise() {
    try {
      if (host.matches(':popover-open')) host.hidePopover();
      host.showPopover();
    } catch {
      /* Popover API unavailable: the max z-index still applies. */
    }
  }

  async function load() {
    try {
      const status = await send('getStatus');
      const { hw } = status;
      if (status.restarting) {
        stateEl.textContent = 'Restart in progress…';
        return;
      }
      if (hw.helper !== 'ok') {
        stateEl.textContent = 'Unknown: helper not available';
        showMsg(`${hw.error || 'The helper is not installed.'} Until then, use "Open setting" to change it by hand.`, true);
        return;
      }
      current = hw.enabled !== false;
      stateEl.textContent = `Currently ${current ? 'on' : 'off'}${hw.pending !== hw.enabled ? ` (${hw.pending ? 'on' : 'off'} after restart)` : ''}`;
      setWanted(current);
      setBusy(false);
    } catch (e) {
      showMsg(e.message, true);
    }
  }

  async function activate(act) {
    if (act === 'close') return remove();
    if (act === 'snooze') {
      remove();
      return send('snooze').catch(() => {});
    }
    if (act === 'setting') return send('openSetting').catch((e) => showMsg(e.message, true));
    if (busy) return;
    if (act === 'toggle') return setWanted(!wanted);
    if (act === 'restart') {
      setBusy(true);
      showMsg('Restarting Opera GX… your tabs will come back.');
      try {
        await send('applyAndRestart', { enabled: wanted });
      } catch (e) {
        showMsg(e.message, true);
        setBusy(false);
      }
    }
  }

  // From the window's point of view, every click inside the closed shadow root targets the
  // host element. Find the real element under the pointer (or the focused one for keyboard
  // clicks) and handle it here, then keep the event away from the page.
  function onClick(ev) {
    if (ev.target !== host) return;
    ev.stopImmediatePropagation();
    ev.preventDefault();
    const el = ev.detail === 0 ? root.activeElement : root.elementFromPoint(ev.clientX, ev.clientY);
    const act = el?.closest?.('[data-act]')?.dataset.act;
    if (act) activate(act);
  }

  function checkCovered() {
    const r = host.getBoundingClientRect();
    if (!r.width) return;
    const top = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
    if (top && top !== host) console.warn('[accelplugin] banner is covered by', top);
  }

  window.__accelpluginBanner = {
    show() {
      if (!host.isConnected) {
        document.documentElement.appendChild(host);
        window.addEventListener('click', onClick, true);
      }
      raise();
      load();
      setTimeout(checkCovered, 1000);
    },
  };
  window.__accelpluginBanner.show();
})();
