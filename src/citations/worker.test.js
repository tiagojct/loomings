import { describe, it, expect, vi } from 'vitest';
import { readFileSync } from 'node:fs';

// Each engine start parses a style and a locale. Under load this takes more than the default 5 s.
vi.setConfig({ testTimeout: 20000 });

const style = readFileSync(new URL('./styles/apa.csl', import.meta.url), 'utf8');
const locale = readFileSync(new URL('./locales/locales-en-US.xml', import.meta.url), 'utf8');

describe('citation worker', () => {
  it('answers analyse messages with the id and stays alive after a bad style', async () => {
    const postMessage = vi.fn();
    const self = { postMessage, onmessage: null };
    vi.stubGlobal('self', self);
    await import('./worker.js');
    const text = '---\nbibliography: r.bib\n---\n[@a]';
    const bib = '@book{a, author = {Smith, J}, title = {T}, year = {2019}}';
    self.onmessage({ data: { id: 1, type: 'sources', sources: { bibs: [{ name: 'r.bib', text: bib }], styleXml: style, localeXml: locale, lang: 'en-US' } } });
    expect(postMessage).not.toHaveBeenCalled();
    self.onmessage({ data: { id: 2, type: 'analyse', text } });
    expect(postMessage.mock.calls[0][0].id).toBe(2);
    expect(postMessage.mock.calls[0][0].report.citations[0].html).toContain('Smith');
    self.onmessage({ data: { id: 3, type: 'sources', sources: { bibs: [], styleXml: 'bad', localeXml: locale, lang: 'en-US' } } });
    self.onmessage({ data: { id: 4, type: 'analyse', text } });
    const last = postMessage.mock.calls[1][0];
    expect(last.id).toBe(4);
    expect(last.report.notes.length).toBe(1);
    expect(last.report.citations[0].markdown).toBe('[@a]');
    vi.unstubAllGlobals();
  });
});
