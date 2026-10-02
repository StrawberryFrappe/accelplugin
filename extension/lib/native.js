// Thin wrapper around the native helper (native-host/host.ps1).

export const HOST_NAME = 'com.accelplugin.hwaccel';

export class HelperError extends Error {
  /** @param {'missing'|'error'} code */
  constructor(message, code) {
    super(message);
    this.code = code;
  }
}

const MISSING_RE = /not found|forbidden|access to the specified native messaging host/i;

export async function callHelper(message) {
  let res;
  try {
    res = await chrome.runtime.sendNativeMessage(HOST_NAME, message);
  } catch (e) {
    const msg = e?.message || String(e);
    if (MISSING_RE.test(msg)) {
      throw new HelperError('Helper not installed. Run native-host\\install.bat, then restart Opera GX.', 'missing');
    }
    throw new HelperError(`Helper failed: ${msg}`, 'error');
  }
  if (!res) throw new HelperError('Helper returned no response.', 'error');
  if (!res.ok) throw new HelperError(res.error || 'Helper reported an error.', 'error');
  return res;
}

/** @returns {Promise<{running: boolean, pending: boolean, localState: string}>} */
export const getState = () => callHelper({ cmd: 'getState' });

/** Close Opera GX, set hardware acceleration, start it again. */
export const applyAndRestart = (enabled, dryRun = false) => callHelper({ cmd: 'apply', enabled: !!enabled, dryRun: !!dryRun });
