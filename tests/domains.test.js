import { test } from 'node:test';
import assert from 'node:assert/strict';
import { normalizeDomain, matchDomain, hostMatches, originPatterns } from '../extension/lib/domains.js';

test('normalizeDomain accepts hosts, URLs and wildcards', () => {
  assert.equal(normalizeDomain('netflix.com'), 'netflix.com');
  assert.equal(normalizeDomain('  Netflix.COM  '), 'netflix.com');
  assert.equal(normalizeDomain('https://www.netflix.com/browse?x=1'), 'netflix.com');
  assert.equal(normalizeDomain('*.crunchyroll.com'), 'crunchyroll.com');
  assert.equal(normalizeDomain('www.disneyplus.com/home'), 'disneyplus.com');
  assert.equal(normalizeDomain('beta.crunchyroll.com:443'), 'beta.crunchyroll.com');
});

test('normalizeDomain rejects junk', () => {
  for (const bad of ['', '   ', 'netflix', 'not a domain', 'http://', null, 42]) {
    assert.equal(normalizeDomain(bad), null, String(bad));
  }
});

test('hostMatches covers subdomains but not lookalikes', () => {
  assert.ok(hostMatches('netflix.com', 'netflix.com'));
  assert.ok(hostMatches('www.netflix.com', 'netflix.com'));
  assert.ok(hostMatches('WWW.NETFLIX.COM.', 'netflix.com'));
  assert.ok(!hostMatches('notnetflix.com', 'netflix.com'));
  assert.ok(!hostMatches('netflix.com.evil.io', 'netflix.com'));
});

test('matchDomain only counts http(s) pages', () => {
  const domains = ['netflix.com', 'crunchyroll.com'];
  assert.equal(matchDomain('https://www.netflix.com/watch/123', domains), 'netflix.com');
  assert.equal(matchDomain('http://crunchyroll.com/', domains), 'crunchyroll.com');
  assert.equal(matchDomain('https://example.com/?q=netflix.com', domains), null);
  assert.equal(matchDomain('chrome://settings', domains), null);
  assert.equal(matchDomain('', domains), null);
  assert.equal(matchDomain(undefined, domains), null);
});

test('originPatterns covers the domain and subdomains', () => {
  assert.deepEqual(originPatterns('netflix.com'), ['*://netflix.com/*', '*://*.netflix.com/*']);
});
