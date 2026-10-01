import { describe, it, expect } from 'vitest';

describe('service worker routing logic', () => {
  const BASE = '/app/';
  function matchAppRoute(pathname) {
    return pathname === '/app' || pathname.startsWith(BASE);
  }

  it('matches /app with and without trailing slash', () => {
    expect(matchAppRoute('/app')).toBe(true);
    expect(matchAppRoute('/app/')).toBe(true);
    expect(matchAppRoute('/app/index.html')).toBe(true);
    expect(matchAppRoute('/app/assets/index-123.js')).toBe(true);
  });

  it('rejects roots and non-app routes', () => {
    expect(matchAppRoute('/')).toBe(false);
    expect(matchAppRoute('/docs/style.css')).toBe(false);
    expect(matchAppRoute('/api')).toBe(false);
    expect(matchAppRoute('/apple-touch-icon.png')).toBe(false);
  });
});
