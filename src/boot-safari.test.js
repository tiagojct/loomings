import { describe, expect, it } from 'vitest';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// The build target is safari14, and the README promises Safari and iPad. The
// build rewrites syntax. It does not rewrite a regular expression or add an
// API. One bad line in the boot chunk stops the whole app on an older Safari,
// also for a document with no citations.
const here = dirname(fileURLToPath(import.meta.url));

const TOO_NEW = [
  ['lookbehind (Safari 16.4)', /\(\?<[=!]/],
  ['Object.hasOwn (Safari 15.4)', /\bObject\.hasOwn\b/],
  ['structuredClone (Safari 15.4)', /\bstructuredClone\(/],
  ['Array.prototype.at (Safari 15.4)', /\.at\(-?\d/],
  ['findLast (Safari 15.4)', /\.findLast(?:Index)?\(/],
  ['Array copies (Safari 16)', /\.to(?:Sorted|Reversed|Spliced)\(/],
  ['Object.groupBy (Safari 17.4)', /\bObject\.groupBy\b/],
  ['Promise.withResolvers (Safari 17.4)', /\bPromise\.withResolvers\b/],
];

/** @param {string} text */
const tooNew = (text) => TOO_NEW.filter(([, pattern]) => pattern.test(text)).map(([name]) => name);

/**
 * Each local module that a static import reaches from `entry`. A dynamic
 * import is not in the boot chunk, so this walk does not follow it.
 *
 * @param {string} entry
 * @returns {string[]}
 */
function bootModules(entry) {
  const seen = new Set([entry]);
  for (const file of seen) {
    const text = readFileSync(file, 'utf8');
    for (const m of text.matchAll(/(?:\bfrom\s*|^\s*import\s+)['"](\.\.?\/[^'"]+\.js)['"]/gm)) {
      seen.add(resolve(dirname(file), m[1]));
    }
  }
  return [...seen];
}

describe('the boot chunk on the build target', () => {
  it('reaches the citation code that the editor loads at boot', () => {
    const modules = bootModules(join(here, 'editor.js'));
    expect(modules).toContain(join(here, 'citations', 'scan.js'));
    expect(modules).toContain(join(here, 'citations', 'document.js'));
    expect(modules).toContain(join(here, 'mermaid.js'));
    expect(modules).not.toContain(join(here, 'citations', 'worker.js'));
  });

  it('has nothing newer than the target in the source of a boot module', () => {
    const found = bootModules(join(here, 'editor.js'))
      .map((file) => [file.slice(here.length + 1), tooNew(readFileSync(file, 'utf8'))])
      .filter(([, names]) => names.length);
    expect(found).toEqual([]);
  });

  it('finds a lookbehind and a new API when they are there', () => {
    expect(tooNew('new RegExp("(?<!x)y")')).toEqual(['lookbehind (Safari 16.4)']);
    expect(tooNew('Object.hasOwn(a, b)')).toEqual(['Object.hasOwn (Safari 15.4)']);
    expect(tooNew('md.inline.ruler.at(name, fn)')).toEqual([]);
  });
});

// This test reads the last build and skips without one.
const DIST = new URL('../dist/', import.meta.url);
describe.skipIf(!existsSync(new URL('index.html', DIST)))('the built boot chunks', () => {
  it('have nothing newer than the target', () => {
    const page = readFileSync(new URL('index.html', DIST), 'utf8');
    const chunks = [...page.matchAll(/\/app\/(assets\/[^"]+\.js)"/g)].map((m) => m[1]);
    expect(chunks.length).toBeGreaterThan(0);
    const found = chunks.map((f) => [f, tooNew(readFileSync(new URL(f, DIST), 'utf8'))]).filter(([, names]) => names.length);
    expect(found).toEqual([]);
  });
});
