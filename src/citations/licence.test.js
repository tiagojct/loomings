import { describe, expect, it } from 'vitest';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { citeprocNotice } from '../../scripts/citeproc-notice.js';

const file = (path) => new URL(path, import.meta.url);

describe('the licences of the citation code', () => {
  it('ships the CSL licence on the web, the same text as beside the styles', () => {
    expect(readFileSync(file('../../public/licenses/CSL-LICENSE.txt'), 'utf8')).toBe(readFileSync(file('./LICENSE-CSL.md'), 'utf8'));
  });

  it('links each licence file from About', () => {
    const page = readFileSync(file('../index.html'), 'utf8');
    for (const name of ['citeproc-LICENSE.txt', 'citation-js-LICENSE.txt', 'CSL-LICENSE.txt']) {
      expect(page).toContain(`data-url="licenses/${name}"`);
      expect(existsSync(file(`../../public/licenses/${name}`))).toBe(true);
    }
  });

  it('names citeproc at the top of the native bundle', () => {
    expect(readFileSync(file('../../macos/Resources/Citations/citations.js'), 'utf8').startsWith(citeprocNotice('LICENSE-citeproc'))).toBe(true);
  });
});

// This test reads the last build and skips without one.
const ASSETS = file('../../dist/assets/');
describe.skipIf(!existsSync(ASSETS))('the built worker', () => {
  it('names citeproc at the top of the only chunk that holds it', () => {
    const chunks = readdirSync(ASSETS).filter((name) => name.endsWith('.js'))
      .map((name) => readFileSync(new URL(name, ASSETS), 'utf8'))
      .filter((code) => code.includes('PROCESSOR_VERSION') || code.includes('citeproc-js'));
    expect(chunks).toHaveLength(1);
    expect(chunks[0].startsWith(citeprocNotice('/app/licenses/citeproc-LICENSE.txt'))).toBe(true);
  });
});
