const $ = (id) => document.getElementById(id);
const toggle = $('toggle');
const restartBtn = $('restart');

let status = null;
let ticker = null;
let renderedAt = Date.now();

async function send(type, extra = {}) {
  const res = await chrome.runtime.sendMessage({ type, ...extra });
  if (!res?.ok) throw new Error(res?.error || 'Extension did not respond.');
  return res.result;
}

function showMsg(text, isError = false) {
  $('msg').textContent = text;
  $('msg').className = isError ? 'err' : 'muted';
  $('msg').hidden = !text;
}

function fmt(ms) {
  const s = Math.ceil(ms / 1000);
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}

function syncButton() {
  if (!status || status.hw.helper !== 'ok') return;
  const current = status.hw.enabled !== false;
  const changing = toggle.checked !== current;
  restartBtn.textContent = changing ? (toggle.checked ? 'Turn on & restart' : 'Turn off & restart') : 'Restart browser';
}

function renderAuto() {
  const { auto, warning, watchedDomain } = status;
  const box = $('auto');
  box.hidden = !auto.eligible;
  if (!auto.eligible) return;
  let text;
  if (warning) text = `Restarting in ${fmt(Math.max(0, warning.deadline - Date.now()))} to turn it back on.`;
  else if (watchedDomain) text = `Auto re-enable paused while ${watchedDomain} is open.`;
  else text = `Turns back on in ${fmt(Math.max(0, auto.remainingMs - (Date.now() - renderedAt)))}.`;
  $('autoText').textContent = text;
  $('postpone').hidden = !warning;
}

function render() {
  const { hw } = status;
  renderedAt = Date.now();
  if (status.restarting) {
    $('state').textContent = 'Restart in progress…';
    toggle.disabled = restartBtn.disabled = true;
  } else if (hw.helper !== 'ok') {
    $('state').textContent = 'Unknown: helper not available';
    toggle.disabled = restartBtn.disabled = true;
    showMsg(hw.error || 'Helper not installed. Run native-host\\install.bat.', true);
  } else {
    const on = hw.enabled !== false;
    toggle.checked = on;
    toggle.disabled = restartBtn.disabled = false;
    const pendingNote = hw.pending !== hw.enabled ? ` (${hw.pending ? 'on' : 'off'} after restart)` : '';
    $('state').textContent = `Currently ${on ? 'on' : 'off'}${pendingNote}`;
    syncButton();
  }
  renderAuto();
  clearInterval(ticker);
  ticker = setInterval(renderAuto, 1000);
}

async function load(refresh) {
  try {
    status = await send(refresh ? 'refresh' : 'getStatus');
    render();
  } catch (e) {
    showMsg(e.message, true);
  }
}

toggle.addEventListener('change', syncButton);

restartBtn.addEventListener('click', async () => {
  restartBtn.disabled = toggle.disabled = true;
  showMsg('Restarting Opera GX… your tabs will come back.');
  try {
    await send('applyAndRestart', { enabled: toggle.checked });
  } catch (e) {
    showMsg(e.message, true);
    restartBtn.disabled = toggle.disabled = false;
  }
});

$('setting').addEventListener('click', () => send('openSetting').catch((e) => showMsg(e.message, true)));
$('postpone').addEventListener('click', async () => {
  await send('postpone').catch((e) => showMsg(e.message, true));
  load(false);
});
$('options').addEventListener('click', (e) => {
  e.preventDefault();
  chrome.runtime.openOptionsPage();
});

load(false).then(() => load(true));
