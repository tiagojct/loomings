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
    for (const name of ['CPAL-1.0.txt', 'citeproc-LICENSE.txt', 'citation-js-LICENSE.txt', 'CSL-LICENSE.txt']) {
      expect(page).toContain(`data-url="licenses/${name}"`);
      expect(existsSync(file(`../../public/licenses/${name}`))).toBe(true);
    }
    expect(page).toContain('data-url="licenses/THIRD-PARTY-NOTICES.txt"');
  });

  it('names citeproc at the top of the native bundle', () => {
    expect(readFileSync(file('../../macos/Resources/Citations/citations.js'), 'utf8').startsWith(citeprocNotice('CPAL-1.0.txt'))).toBe(true);
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
    expect(chunks[0].startsWith(citeprocNotice('/app/licenses/CPAL-1.0.txt'))).toBe(true);
  });

  it('ships complete third-party notices and precaches every JS chunk and licence file', () => {
    const noticesPath = file('../../dist/licenses/THIRD-PARTY-NOTICES.txt');
    expect(existsSync(noticesPath)).toBe(true);
    const notices = readFileSync(noticesPath, 'utf8');
    expect(notices).toContain('citeproc');
    expect(notices).toContain('@codemirror/');
    expect(notices).toContain('markdown-it');
    expect(notices).toContain('Copyright (c) 2026 Tiago Jacinto');
    expect(notices).toContain('Common Public Attribution License Version 1.0 (CPAL)');

    const sw = readFileSync(file('../../dist/sw.js'), 'utf8');
    const jsChunks = readdirSync(ASSETS).filter((name) => name.endsWith('.js'));
    for (const chunk of jsChunks) {
      expect(sw).toContain(`/app/assets/${chunk}`);
    }
    const licenseFiles = readdirSync(file('../../dist/licenses/')).filter((name) => name.endsWith('.txt'));
    expect(licenseFiles).toContain('THIRD-PARTY-NOTICES.txt');
    expect(licenseFiles).toContain('CPAL-1.0.txt');
    for (const licenseFile of licenseFiles) {
      expect(sw).toContain(`/app/licenses/${licenseFile}`);
    }
  });
});
