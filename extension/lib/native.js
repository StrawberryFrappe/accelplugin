// Thin wrapper around the native helper (native-host/host.ps1).
import { ext } from './ext.js';
import { currentBrowser, currentBrowserName } from './browser.js';

export const HOST_NAME = 'com.accelplugin.hwaccel';

export class HelperError extends Error {
  /** @param {'missing'|'error'} code */
  constructor(message, code) {
    super(message);
    this.code = code;
  }
}

// Chromium: "Specified native messaging host not found." Firefox: "No such native application ...".
const MISSING_RE = /not found|forbidden|access to the specified native messaging host|no such native application/i;

export async function callHelper(message) {
  let res;
  try {
    res = await ext.runtime.sendNativeMessage(HOST_NAME, { ...message, browser: currentBrowser });
  } catch (e) {
    const msg = e?.message || String(e);
    if (MISSING_RE.test(msg)) {
      throw new HelperError(`Helper not installed. Run native-host\\install.bat, select ${currentBrowserName}, then restart it.`, 'missing');
    }
    throw new HelperError(`Helper failed: ${msg}`, 'error');
  }
  if (!res) throw new HelperError('Helper returned no response.', 'error');
  if (!res.ok) throw new HelperError(res.error || 'Helper reported an error.', 'error');
  return res;
}

/** @returns {Promise<{running: boolean, pending: boolean, localState: string}>} */
export const getState = () => callHelper({ cmd: 'getState' });

/** Close the browser, set hardware acceleration, start it again. */
export const applyAndRestart = (enabled, dryRun = false) => callHelper({ cmd: 'apply', enabled: !!enabled, dryRun: !!dryRun });
