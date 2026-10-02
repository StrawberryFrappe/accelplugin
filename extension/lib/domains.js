// Domain helpers. Pure functions so they can be unit-tested outside the browser.

export const DEFAULT_DOMAINS = ['netflix.com', 'crunchyroll.com'];

const DOMAIN_RE = /^(localhost|[a-z0-9-]+(\.[a-z0-9-]+)+)$/;

/**
 * Turn user input ("https://www.Netflix.com/browse", "*.crunchyroll.com", "netflix.com")
 * into a bare registrable-ish host ("netflix.com"). Returns null if it doesn't look like a host.
 */
export function normalizeDomain(input) {
  if (typeof input !== 'string') return null;
  let s = input.trim().toLowerCase();
  if (!s) return null;
  if (/^[a-z][a-z0-9+.-]*:\/\//.test(s)) {
    try {
      s = new URL(s).hostname;
    } catch {
      return null;
    }
  }
  s = s
    .replace(/^\*\./, '')
    .replace(/[/?#].*$/, '')
    .replace(/:\d+$/, '')
    .replace(/\.$/, '')
    .replace(/^www\./, '');
  return DOMAIN_RE.test(s) ? s : null;
}

/** True if `hostname` is `domain` or a subdomain of it. */
export function hostMatches(hostname, domain) {
  const h = String(hostname || '').toLowerCase().replace(/\.$/, '');
  return h === domain || h.endsWith('.' + domain);
}

/** Returns the watched domain that `url` belongs to, or null. Only http(s) pages count. */
export function matchDomain(url, domains) {
  if (!url) return null;
  let u;
  try {
    u = new URL(url);
  } catch {
    return null;
  }
  if (u.protocol !== 'http:' && u.protocol !== 'https:') return null;
  return domains.find((d) => hostMatches(u.hostname, d)) || null;
}

/** Host permission match patterns covering a domain and its subdomains. */
export function originPatterns(domain) {
  return [`*://${domain}/*`, `*://*.${domain}/*`];
}
