// The WebExtension API namespace: `browser` in Firefox (promise-based), `chrome` elsewhere.
export const ext = globalThis.browser ?? globalThis.chrome;
