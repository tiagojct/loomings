import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';

// nginx inherits add_header from the server only when the location has no
// add_header of its own. The assets location sets Cache-Control, so it must
// repeat the security headers through the same snippet. This test encodes
// that rule, because the mistake is invisible in a browser.
const root = fileURLToPath(new URL('..', import.meta.url));
const conf = readFileSync(join(root, 'nginx.conf'), 'utf8');
const dockerfile = readFileSync(join(root, 'Dockerfile'), 'utf8');
const SNIPPET = 'include /etc/nginx/snippets/security-headers.conf;';

describe('nginx security headers', () => {
  it('keeps the headers in one snippet', () => {
    const snippet = readFileSync(join(root, 'nginx-security-headers.conf'), 'utf8');
    expect(snippet).toContain('Content-Security-Policy');
    expect(snippet).toContain('X-Content-Type-Options');
    expect(snippet).toContain('Referrer-Policy');
  });

  it('includes the snippet at the server level', () => {
    expect(conf).toContain(SNIPPET);
  });

  it('repeats the snippet in every location that adds its own header', () => {
    const locations = [...conf.matchAll(/location\s+[^{]+\{([\s\S]*?)\}/g)];
    expect(locations.length).toBeGreaterThan(0);
    for (const [, body] of locations) {
      if (/\badd_header\b/.test(body)) expect(body).toContain(SNIPPET);
    }
  });

  it('copies the snippet into the image', () => {
    expect(dockerfile).toMatch(/COPY nginx-security-headers\.conf \/etc\/nginx\/snippets\/security-headers\.conf/);
  });
});
