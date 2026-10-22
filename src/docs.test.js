import { describe, it, expect } from 'vitest';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { extname, join } from 'node:path';
import { FAMILY_ORDER } from './palettes.js';

// The landing page is hand-written and hand-cache-busted, which is exactly how
// it has broken before: a reference to a file that moved, a ?v= that stopped
// matching, a font that never shipped. These checks are cheap and read-only.
const root = fileURLToPath(new URL('..', import.meta.url));
const docs = join(root, 'docs');
const html = readFileSync(join(docs, 'index.html'), 'utf8');
const css = readFileSync(join(docs, 'style.css'), 'utf8');

describe('landing page references', () => {
  const refs = [...html.matchAll(/(?:href|src)="([^"]+)"/g)].map((m) => m[1]);
  const local = refs.filter((ref) =>
    !/^(https?:|mailto:|#)/.test(ref) && !ref.startsWith('/app/')
  );

  it('every local file it references exists', () => {
    for (const ref of local) {
      const path = ref.split('?')[0];
      const file = join(docs, path);
      expect(existsSync(file), `${ref} -> docs/${path}`).toBe(true);
    }
  });

  it('every local stylesheet or script is cache-busted with a version', () => {
    for (const ref of local) {
      if (!['.css', '.js'].includes(extname(ref.split('?')[0]))) continue;
      expect(ref, ref).toMatch(/\?v=\d+\.\d+\.\d+$/);
    }
  });

  it('the social card is referenced and exists', () => {
    expect(html).toMatch(/og:image" content="[^"]*assets\/og\.png\?v=\d+\.\d+\.\d+"/);
    expect(existsSync(join(docs, 'assets/og.png'))).toBe(true);
  });
});

describe('landing page fonts', () => {
  // The landing page borrows the app's self-hosted faces from /app/fonts.
  const urls = [...css.matchAll(/url\('(\/app\/fonts\/[^']+)'\)/g)].map((m) => m[1]);

  it('declares the faces it loads', () => {
    expect(urls.length).toBeGreaterThanOrEqual(6);
  });

  it('every face it points at exists in the app’s public directory', () => {
    for (const url of urls) {
      const file = join(root, 'public', url.replace('/app/', ''));
      expect(existsSync(file), url).toBe(true);
    }
  });
});

describe('landing page colour cards', () => {
  const cards = [...html.matchAll(/class="binding" href="\/app\/\?theme=([a-z]+)"/g)].map((m) => m[1]);

  it('offers exactly the families the editor ships', () => {
    expect(cards).toHaveLength(FAMILY_ORDER.length);
    expect([...cards].sort()).toEqual([...FAMILY_ORDER].sort());
  });

  it('gives every card an accessible name', () => {
    const labels = [...html.matchAll(/class="binding"[^>]*aria-label="Open the editor in ([^"]+)"/g)];
    expect(labels).toHaveLength(FAMILY_ORDER.length);
  });
});
