// Injected by background.js into watched sites when hardware acceleration is on.
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

  const host = document.createElement('div');
  host.style.cssText = 'all: initial; position: fixed; top: 16px; right: 16px; z-index: 2147483647;';
  const root = host.attachShadow({ mode: 'closed' });
  root.innerHTML = `
    <style>
      :host { all: initial; }
      .card {
        width: 360px; max-width: calc(100vw - 32px); box-sizing: border-box; padding: 16px 18px 14px;
        font: 13px/1.45 system-ui, -apple-system, "Segoe UI", sans-serif; color: #ececf1;
        background: #17161d; border: 1px solid #2c2a36; border-left: 3px solid #fa1e4e;
        border-radius: 10px; box-shadow: 0 12px 32px rgba(0, 0, 0, .45);
        animation: in .18s ease-out;
      }
      @keyframes in { from { opacity: 0; transform: translateY(-6px); } }
      .head { display: flex; align-items: start; gap: 8px; }
      h1 { flex: 1; margin: 0 0 4px; font-size: 14px; font-weight: 600; }
      p { margin: 0 0 12px; color: #a9a7b6; }
      .x { all: unset; cursor: pointer; color: #77758a; font-size: 18px; line-height: 1; padding: 0 2px; }
      .x:hover { color: #ececf1; }
      .setting {
        display: flex; align-items: center; justify-content: space-between;
        padding: 10px 12px; margin-bottom: 12px; background: #201f28; border-radius: 8px;
      }
      .setting small { display: block; color: #8a8898; font-size: 11px; }
      .switch { position: relative; width: 38px; height: 22px; flex: none; }
      .switch input { position: absolute; inset: 0; opacity: 0; margin: 0; cursor: pointer; }
      .track { position: absolute; inset: 0; border-radius: 11px; background: #3a3846; transition: background .15s; pointer-events: none; }
      .track::after {
        content: ''; position: absolute; top: 3px; left: 3px; width: 16px; height: 16px;
        border-radius: 50%; background: #fff; transition: transform .15s;
      }
      input:checked + .track { background: #fa1e4e; }
      input:checked + .track::after { transform: translateX(16px); }
      input:disabled + .track { opacity: .4; }
      input:focus-visible + .track { outline: 2px solid #fa1e4e; outline-offset: 2px; }
      .actions { display: flex; gap: 8px; align-items: center; }
      button.primary, button.ghost {
        all: unset; cursor: pointer; padding: 7px 12px; border-radius: 6px; font-weight: 600; font-size: 12.5px; white-space: nowrap;
      }
      button.primary { background: #fa1e4e; color: #fff; }
      button.primary:hover { background: #ff3b66; }
      button.ghost { color: #a9a7b6; }
      button.ghost:hover { color: #ececf1; background: #24232c; }
      button[disabled] { opacity: .5; pointer-events: none; }
      .link { all: unset; cursor: pointer; margin-left: auto; white-space: nowrap; color: #8a8898; font-size: 11.5px; text-decoration: underline; }
      .link:hover { color: #ececf1; }
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
      <label class="setting">
        <span>Use hardware acceleration when available<small class="state">Checking…</small></span>
        <span class="switch"><input type="checkbox" class="toggle" checked disabled><span class="track"></span></span>
      </label>
      <div class="actions">
        <button class="primary" data-act="restart" disabled>Restart browser</button>
        <button class="ghost" data-act="snooze">Not now</button>
        <button class="link" data-act="setting">Open setting</button>
      </div>
      <div class="msg" hidden></div>
    </div>`;

  const $ = (sel) => root.querySelector(sel);
  const toggle = $('.toggle');
  const restartBtn = $('[data-act="restart"]');
  const stateEl = $('.state');
  const msgEl = $('.msg');
  let current = null; // running state reported by the helper

  function showMsg(text, isError = false) {
    msgEl.textContent = text;
    msgEl.classList.toggle('err', isError);
    msgEl.hidden = !text;
  }

  function syncButton() {
    if (current === null) return;
    const changing = toggle.checked !== current;
    restartBtn.textContent = changing ? (toggle.checked ? 'Turn on & restart' : 'Turn off & restart') : 'Restart browser';
  }

  function remove() {
    host.remove();
  }

  async function load() {
    try {
      const status = await send('getStatus');
      const { hw } = status;
      if (status.restarting) {
        toggle.disabled = true;
        restartBtn.disabled = true;
        stateEl.textContent = 'Restart in progress…';
        return;
      }
      if (hw.helper !== 'ok') {
        stateEl.textContent = 'Unknown: helper not available';
        showMsg(`${hw.error || 'The helper is not installed.'} Until then, use "Open setting" to change it by hand.`, true);
        return;
      }
      current = hw.enabled !== false;
      toggle.checked = current;
      toggle.disabled = false;
      restartBtn.disabled = false;
      stateEl.textContent = `Currently ${current ? 'on' : 'off'}${hw.pending !== hw.enabled ? ` (${hw.pending ? 'on' : 'off'} after restart)` : ''}`;
      syncButton();
    } catch (e) {
      showMsg(e.message, true);
    }
  }

  toggle.addEventListener('change', syncButton);

  root.addEventListener('click', async (ev) => {
    const act = ev.target.closest?.('[data-act]')?.dataset.act;
    if (!act) return;
    if (act === 'close') return remove();
    if (act === 'snooze') {
      await send('snooze').catch(() => {});
      return remove();
    }
    if (act === 'setting') {
      await send('openSetting').catch((e) => showMsg(e.message, true));
      return;
    }
    if (act === 'restart') {
      restartBtn.disabled = true;
      toggle.disabled = true;
      showMsg('Restarting Opera GX… your tabs will come back.');
      try {
        await send('applyAndRestart', { enabled: toggle.checked });
      } catch (e) {
        showMsg(e.message, true);
        restartBtn.disabled = false;
        toggle.disabled = false;
      }
    }
  });

  window.__accelpluginBanner = {
    show() {
      if (!host.isConnected) document.documentElement.appendChild(host);
      load();
    },
  };
  window.__accelpluginBanner.show();
})();
