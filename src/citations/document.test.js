import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { readFileSync } from 'node:fs';
import { createCitationDocument, citedHtml, referencesHtml } from './document.js';
import * as library from './library.js';
import { createSession } from './session.js';
import { renderPreview, renderMarkdown } from '../markdown.js';

const WITH_BIB = '---\nbibliography: refs.bib\n---\n\nText [@a].\n';
const stubAssets = {
  loadBundledStyle: async () => '<style/>',
  loadLocale: async (lang) => ({ lang: lang ?? 'en-US', xml: '<locale/>' }),
};
const report = (name = 'r') => ({
  name, citations: [], bibliography: [], bibliographyMarkdown: '', library: [], notes: [], markdownSource: '',
});

function fakeClient() {
  /** @type {any} */
  const c = { listeners: [], sources: [], asked: [] };
  c.onReport = (listener) => c.listeners.push(listener);
  c.setSources = vi.fn(async (s) => { c.sources.push(s); });
  c.update = vi.fn((text) => { c.asked.push(text); });
  c.answer = (r) => { for (const l of c.listeners) l(r); };
  return c;
}

function setup(overrides = {}) {
  const client = fakeClient();
  const options = {
    client: vi.fn(async () => client),
    assets: vi.fn(async () => stubAssets),
    listFiles: vi.fn(async () => [{ name: 'refs.bib', kind: 'bib', text: '@book{a}' }]),
    onChange: vi.fn(),
    library: async () => library,
    ...overrides,
  };
  return { client, options, doc: createCitationDocument(options) };
}

const settle = () => vi.advanceTimersByTimeAsync(0);
const typed = (doc, text) => { doc.update(text); return vi.advanceTimersByTimeAsync(300); };

describe('createCitationDocument', () => {
  beforeEach(() => { vi.useFakeTimers(); });
  afterEach(() => { vi.useRealTimers(); });

  it('loads nothing for a document with no bibliography and no references', async () => {
    const { doc, options } = setup();
    await typed(doc, '# Plain\n\nMail [@a].\n');
    await expect(doc.flush('# Plain\n\nMail [@a].\n')).resolves.toBe(null);
    expect(options.client).not.toHaveBeenCalled();
    expect(options.assets).not.toHaveBeenCalled();
    expect(options.listFiles).not.toHaveBeenCalled();
    expect(doc.current()).toBe(null);
  });

  it('starts for a document with only a references line', async () => {
    const { doc, client } = setup();
    await typed(doc, '---\nreferences: [{"id":"a","type":"book"}]\n---\n[@a]\n');
    expect(client.asked).toHaveLength(1);
  });

  it('waits 300 ms and asks only for the last text', async () => {
    const { doc, client } = setup();
    doc.update(`${WITH_BIB}1`);
    await vi.advanceTimersByTimeAsync(299);
    doc.update(`${WITH_BIB}2`);
    await vi.advanceTimersByTimeAsync(299);
    expect(client.update).not.toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(1);
    expect(client.asked).toEqual([`${WITH_BIB}2`]);
  });

  it('reads a text from a function only when the wait ends', async () => {
    const { doc, client } = setup();
    const read = vi.fn(() => WITH_BIB);
    doc.update(read);
    doc.update(read);
    expect(read).not.toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(300);
    expect(read).toHaveBeenCalledTimes(1);
    expect(client.asked).toEqual([WITH_BIB]);
  });

  it('sets the sources only when the meta or the files change', async () => {
    const { doc, client, options } = setup();
    await typed(doc, WITH_BIB);
    client.answer(report());
    await settle();
    await typed(doc, `${WITH_BIB}more`);
    client.answer(report());
    await settle();
    expect(client.setSources).toHaveBeenCalledTimes(1);
    expect(options.listFiles).toHaveBeenCalledTimes(1);
    await typed(doc, WITH_BIB.replace('---\n\n', 'csl: apa\n---\n\n'));
    expect(client.setSources).toHaveBeenCalledTimes(2);
    expect(options.listFiles).toHaveBeenCalledTimes(1);
  });

  it('gives the files to the client as sources', async () => {
    const { doc, client } = setup();
    await typed(doc, WITH_BIB);
    expect(client.sources[0].bibs).toEqual([{ name: 'refs.bib', text: '@book{a}' }]);
    expect(client.sources[0].missing).toEqual([]);
  });

  it('holds each report with the text that it is for', async () => {
    const { doc, client, options } = setup();
    await typed(doc, WITH_BIB);
    expect(doc.current()).toBe(null);
    const first = report();
    client.answer(first);
    await settle();
    expect(doc.current()).toEqual({ text: WITH_BIB, report: first });
    expect(options.onChange).toHaveBeenCalledTimes(1);
    doc.update(`${WITH_BIB}more`);
    expect(doc.current()).toEqual({ text: WITH_BIB, report: first });
  });

  it('does not ask again while an answer is pending, and then asks for the last text', async () => {
    const { doc, client } = setup();
    await typed(doc, `${WITH_BIB}1`);
    await typed(doc, `${WITH_BIB}2`);
    await typed(doc, `${WITH_BIB}3`);
    expect(client.asked).toEqual([`${WITH_BIB}1`]);
    client.answer(report());
    await settle();
    expect(client.asked).toEqual([`${WITH_BIB}1`, `${WITH_BIB}3`]);
  });

  it('does not tell the page about a report for an older text', async () => {
    const { doc, client, options } = setup();
    await typed(doc, `${WITH_BIB}1`);
    doc.update(`${WITH_BIB}2`);
    await vi.advanceTimersByTimeAsync(300);
    client.answer(report());
    await settle();
    expect(options.onChange).not.toHaveBeenCalled();
    client.answer(report());
    await settle();
    expect(options.onChange).toHaveBeenCalledTimes(1);
  });

  it('flush waits for the report of exactly this text, also when the user types', async () => {
    const { doc, client } = setup();
    let done = null;
    doc.flush(WITH_BIB).then((r) => { done = r; });
    await settle();
    expect(client.asked).toEqual([WITH_BIB]);
    await typed(doc, `${WITH_BIB}typed`);
    expect(done).toBe(null);
    const first = report('first');
    client.answer(first);
    await settle();
    expect(done).toBe(first);
    expect(client.asked).toEqual([WITH_BIB, `${WITH_BIB}typed`]);
  });

  it('flush does not wait for the debounce', async () => {
    const { doc, client } = setup();
    doc.update(WITH_BIB);
    const flushed = doc.flush(WITH_BIB);
    await settle();
    expect(client.asked).toEqual([WITH_BIB]);
    client.answer(report());
    await flushed;
    await vi.advanceTimersByTimeAsync(300);
    expect(client.asked).toEqual([WITH_BIB]);
  });

  it('flush uses the held report of the same text and asks nothing', async () => {
    const { doc, client } = setup();
    await typed(doc, WITH_BIB);
    const held = report();
    client.answer(held);
    await settle();
    await expect(doc.flush(WITH_BIB)).resolves.toBe(held);
    expect(client.asked).toHaveLength(1);
  });

  it('refresh reads the files again and asks for the last text', async () => {
    const files = [{ name: 'refs.bib', kind: 'bib', text: 'one' }];
    const { doc, client, options } = setup({ listFiles: vi.fn(async () => files.map((f) => ({ ...f }))) });
    await typed(doc, WITH_BIB);
    client.answer(report());
    await settle();
    files[0].text = 'two';
    const refreshed = doc.refresh();
    await settle();
    expect(options.listFiles).toHaveBeenCalledTimes(2);
    expect(client.sources[1].bibs[0].text).toBe('two');
    const fresh = report('fresh');
    client.answer(fresh);
    await refreshed;
    expect(doc.current()?.report).toBe(fresh);
  });

  it('a file added during a read of the files is not lost', async () => {
    let release = () => {};
    const listFiles = vi.fn()
      .mockImplementationOnce(() => new Promise((resolve) => { release = () => resolve([]); }))
      .mockImplementation(async () => [{ name: 'refs.bib', kind: 'bib', text: 'new' }]);
    const { doc, client } = setup({ listFiles });
    doc.flush(WITH_BIB);
    await settle();
    doc.refresh();
    release();
    await settle();
    client.answer(report());
    await settle();
    expect(client.sources.at(-1).bibs[0].text).toBe('new');
  });

  it('does nothing on refresh before the first text', async () => {
    const { doc, options } = setup();
    await expect(doc.refresh()).resolves.toBe(null);
    expect(options.listFiles).not.toHaveBeenCalled();
  });

  it('reports a missing file and does not throw', async () => {
    const { doc, client } = setup({ listFiles: vi.fn(async () => []) });
    await typed(doc, WITH_BIB);
    expect(client.sources[0].missing).toEqual(['refs.bib']);
    expect(client.asked).toEqual([WITH_BIB]);
  });

  it('gives null when the client code does not load, and tries again', async () => {
    const client = fakeClient();
    const loader = vi.fn().mockRejectedValueOnce(new Error('offline')).mockResolvedValue(client);
    const { doc } = setup({ client: loader });
    await expect(doc.flush(WITH_BIB)).resolves.toBe(null);
    const second = doc.flush(WITH_BIB);
    await settle();
    expect(client.asked).toEqual([WITH_BIB]);
    client.answer(report());
    await expect(second).resolves.not.toBe(null);
  });

  it('still asks when the file list or the assets fail, and tries the sources again', async () => {
    const assets = vi.fn().mockRejectedValueOnce(new Error('offline')).mockResolvedValue(stubAssets);
    const { doc, client } = setup({ assets });
    const first = doc.flush(WITH_BIB);
    await settle();
    expect(client.sources[0]).toEqual({});
    client.answer(report());
    await first;
    await typed(doc, `${WITH_BIB}more`);
    expect(client.sources[1].bibs).toHaveLength(1);
  });

  it('accepts an answer that comes inside client.update', async () => {
    const { doc, client } = setup();
    const answer = report();
    client.update = vi.fn(() => client.answer(answer));
    await expect(doc.flush(WITH_BIB)).resolves.toBe(answer);
  });

  it('keeps working when a page update throws', async () => {
    const onChange = vi.fn().mockImplementationOnce(() => { throw new Error('page'); });
    const logged = vi.spyOn(console, 'error').mockImplementation(() => {});
    const { doc, client } = setup({ onChange });
    await typed(doc, WITH_BIB);
    client.answer(report());
    await settle();
    await typed(doc, `${WITH_BIB}more`);
    expect(client.asked).toHaveLength(2);
    expect(logged).toHaveBeenCalledTimes(1);
    logged.mockRestore();
  });

  it('drops the report when the document loses its bibliography', async () => {
    const { doc, client } = setup();
    await typed(doc, WITH_BIB);
    client.answer(report());
    await settle();
    await typed(doc, 'no front matter');
    expect(doc.current()).toBe(null);
  });
});

describe('referencesHtml', () => {
  it('is empty with no entries, also with a title', () => {
    expect(referencesHtml('Refs', [])).toBe('');
  });
  it('holds the entries, with no heading when there is no title', () => {
    expect(referencesHtml(null, ['<div class="csl-entry">A</div>', '<div class="csl-entry">B</div>']))
      .toBe('<section class="references"><div class="csl-entry">A</div><div class="csl-entry">B</div></section>');
  });
  it('escapes the title', () => {
    expect(referencesHtml('<b>R&D</b>', ['x'])).toContain('<h2>&lt;b&gt;R&amp;D&lt;/b&gt;</h2>');
  });
});

describe('citedHtml', () => {
  const source = '---\nbibliography: r.bib\nreference-section-title: Referências\n---\n\nText [@a].\n';
  const from = source.indexOf('[@a]');
  const cited = {
    ...report(),
    citations: [{ from, to: from + 4, html: '(A 2020)', markdown: '(A 2020)', missing: [] }],
    bibliography: ['<div class="csl-entry">A. 2020.</div>'],
  };

  it('renders exactly as the renderer with no report', () => {
    expect(citedHtml(source, null, renderPreview)).toBe(renderPreview(source));
  });

  it('puts the citations and the references in the preview', () => {
    const html = citedHtml(source, cited, renderPreview);
    expect(html).toContain('<span class="cite">(A 2020)</span>');
    expect(html).not.toContain('[@a]');
    expect(html.endsWith('<section class="references"><h2>Referências</h2><div class="csl-entry">A. 2020.</div></section>')).toBe(true);
  });

  it('uses the same path for the export renderer', () => {
    const html = citedHtml(source, cited, renderMarkdown);
    expect(html).toContain('<span class="cite">(A 2020)</span>');
    expect(html).toContain('<section class="references">');
  });

  it('keeps the data-line values of the blocks', () => {
    const lines = (html) => [...html.matchAll(/data-line="(\d+)"/g)].map((m) => m[1]);
    expect(lines(citedHtml(source, cited, renderPreview))).toEqual(lines(renderPreview(source)));
  });

  it('marks an unknown key and adds no empty section', () => {
    const unknown = { ...report(), citations: [{ from, to: from + 4, html: '[@a]', markdown: '[@a]', missing: ['a'] }] };
    const html = citedHtml(source, unknown, renderPreview);
    expect(html).toContain('<span class="cite cite-missing">[@a]</span>');
    expect(html).not.toContain('references');
  });
});

describe('document, session and output together', () => {
  const style = readFileSync(new URL('./styles/vancouver.csl', import.meta.url), 'utf8');
  const locale = readFileSync(new URL('./locales/locales-pt-PT.xml', import.meta.url), 'utf8');
  const english = readFileSync(new URL('./locales/locales-en-US.xml', import.meta.url), 'utf8');

  it('gives a numbered reference with a real session', { timeout: 20000 }, async () => {
    const session = createSession();
    /** @type {any} */
    const client = {
      listener: null,
      onReport(listener) { this.listener = listener; },
      async setSources(sources) { session.setSources(sources); },
      update(text) { this.listener(session.analyse(text)); },
    };
    const doc = createCitationDocument({
      client: async () => client,
      assets: async () => ({
        loadBundledStyle: async (id) => (id === 'vancouver' ? style : null),
        loadLocale: async (lang) => ({ lang: lang === 'pt-PT' ? 'pt-PT' : 'en-US', xml: lang === 'pt-PT' ? locale : english }),
      }),
      listFiles: async () => [{ name: 'refs.bib', kind: 'bib', text: '@book{a, author = {Smith, John}, title = {A book}, year = {2019}}' }],
      onChange: () => {},
    });
    const text = '---\nbibliography: refs.bib\ncsl: vancouver\nlang: pt-PT\n---\n\nText [@a] and [@none].\n';
    const html = citedHtml(text, await doc.flush(text), renderPreview);
    expect(html).toMatch(/<span class="cite">\(?1\)?<\/span>/);
    expect(html).toContain('<span class="cite cite-missing">[@none]</span>');
    expect(html).toContain('<section class="references">');
    expect(html).toContain('csl-left-margin');
    expect(html).toContain('csl-right-inline');
    expect(html).toContain('Smith J');
  });
});
