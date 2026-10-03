// Which browser the extension is running in. The helper uses this as a hint (it also checks
// which process started it), and the UI uses it for names and settings links.
import { ext } from './ext.js';

export const BROWSERS = {
  operagx: {
    name: 'Opera GX',
    settingsUrls: ['opera://settings/?search=hardware%20acceleration', 'chrome://settings/?search=hardware%20acceleration'],
  },
  chrome: {
    name: 'Google Chrome',
    settingsUrls: ['chrome://settings/?search=hardware%20acceleration'],
  },
  brave: {
    name: 'Brave',
    settingsUrls: ['brave://settings/?search=hardware%20acceleration', 'chrome://settings/?search=hardware%20acceleration'],
  },
  firefox: {
    name: 'Firefox',
    // Extensions can't open about:preferences, so the UI shows this instead.
    settingsUrls: [],
    manualHint:
      'Open about:preferences, go to General → Performance, untick "Use recommended performance settings", then change "Use hardware acceleration when available".',
  },
};

/** @param {{runtime?: object}} [api] @param {Navigator} [nav] */
export function detectBrowser(api = ext, nav = globalThis.navigator) {
  if (typeof api?.runtime?.getBrowserInfo === 'function') return 'firefox';
  const brands = (nav?.userAgentData?.brands || []).map((b) => b.brand);
  if (nav?.brave || brands.some((b) => /brave/i.test(b))) return 'brave';
  if (/\bOPR\//.test(nav?.userAgent || '') || brands.some((b) => /opera/i.test(b))) return 'operagx';
  return 'chrome';
}

export const currentBrowser = detectBrowser();
export const currentBrowserName = BROWSERS[currentBrowser].name;
