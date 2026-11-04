import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { readFileSync } from 'node:fs';
import {
  createCitationDocument, citedHtml, referencesHtml, citationsLeftLiteral, metaPrefix, documentMeta, documentUsesCitations,
} from './document.js';
import { readCitationMeta } from './frontmatter.js';
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
  c.shareSource = vi.fn(async (text) => `${text}shared`);
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

describe('reportFor', () => {
  beforeEach(() => { vi.useFakeTimers(); });
  afterEach(() => { vi.useRealTimers(); });

  const head = '---\nbibliography: refs.bib\n---\n\n';
  /** A report for `text`, with one output for each citation slice. */
  const reportOf = (text, slices) => ({
    ...report(),
    citations: slices.map(([slice, html, at = 0]) => {
      const from = text.indexOf(slice, at);
      return { from, to: from + slice.length, html, markdown: html, missing: [] };
    }),
    bibliography: ['<div class="csl-entry">A.</div>'],
    notes: [{ from: 0, to: 0, message: 'a note' }],
  });
  async function held(text, slices) {
    const set = setup();
    await typed(set.doc, text);
    const given = reportOf(text, slices);
    set.client.answer(given);
    await settle();
    return { ...set, given };
  }

  it('gives null with no report', () => {
    expect(setup().doc.reportFor(WITH_BIB)).toBe(null);
  });

  it('gives the report itself for its own text', async () => {
    const text = `${head}Text [@a].\n`;
    const { doc, given } = await held(text, [['[@a]', '(A 2020)']]);
    expect(doc.reportFor(text)).toBe(given);
  });

  it('moves a citation after an edit before it, with no call to the worker', async () => {
    const text = `${head}Text [@a].\n`;
    const { doc, client, given } = await held(text, [['[@a]', '(A 2020)']]);
    const edited = `${head}New words. Text [@a].\n`;
    const moved = doc.reportFor(edited);
    expect(moved.citations).toHaveLength(1);
    expect(moved.citations[0].html).toBe('(A 2020)');
    expect(edited.slice(moved.citations[0].from, moved.citations[0].to)).toBe('[@a]');
    expect(moved.bibliography).toEqual(given.bibliography);
    expect(moved.notes).toEqual(given.notes);
    expect(client.asked).toHaveLength(1);
  });

  it('keeps the citations and the references in the preview during an edit', async () => {
    const text = `${head}Text [@a].\n`;
    const { doc } = await held(text, [['[@a]', '(A 2020)']]);
    const edited = `${head}New words. Text [@a].\n`;
    const html = citedHtml(edited, doc.reportFor(edited), renderPreview);
    expect(html).toContain('<span class="cite">(A 2020)</span>');
    expect(html).not.toContain('[@a]');
    expect(html).toContain('<section class="references">');
  });

  it('leaves a new slice literal until its report arrives', async () => {
    const text = `${head}Text [@a].\n`;
    const { doc } = await held(text, [['[@a]', '(A 2020)']]);
    const edited = `${head}Text [@a] and [@new].\n`;
    const moved = doc.reportFor(edited);
    expect(moved.citations.map((c) => c.html)).toEqual(['(A 2020)']);
    const html = citedHtml(edited, moved, renderPreview);
    expect(html).toContain('<span class="cite">(A 2020)</span>');
    expect(html).toContain('[@new]');
    expect(html).not.toContain('cite-missing');
  });

  it('reuses equal slices in order, and the last one for an added copy', async () => {
    const text = `${head}One [@a]. Two [@a].\n`;
    const { doc } = await held(text, [['[@a]', 'first'], ['[@a]', 'second', text.indexOf('Two')]]);
    const edited = `${head}Zero. One [@a]. Two [@a]. Three [@a].\n`;
    expect(doc.reportFor(edited).citations.map((c) => c.html)).toEqual(['first', 'second', 'second']);
  });

  it('keeps the unknown mark of a moved citation', async () => {
    const text = `${head}Text [@a].\n`;
    const set = setup();
    await typed(set.doc, text);
    const given = reportOf(text, [['[@a]', '[@a]']]);
    given.citations[0].missing = ['a'];
    set.client.answer(given);
    await settle();
    expect(set.doc.reportFor(`${head}More. Text [@a].\n`).citations[0].missing).toEqual(['a']);
  });

  it('gives null when the style, the language or the files change', async () => {
    const text = `${head}Text [@a].\n`;
    const { doc } = await held(text, [['[@a]', '(A 2020)']]);
    expect(doc.reportFor(text.replace('---\n\n', 'csl: apa\n---\n\n'))).toBe(null);
    expect(doc.reportFor(text.replace('---\n\n', 'lang: pt-PT\n---\n\n'))).toBe(null);
    expect(doc.reportFor(text.replace('refs.bib', 'other.bib'))).toBe(null);
  });

  it('gives null when the document no longer uses citations', async () => {
    const text = `${head}Text [@a].\n`;
    const { doc } = await held(text, [['[@a]', '(A 2020)']]);
    expect(doc.reportFor('Text [@a].\n')).toBe(null);
  });
});

describe('the time limit of flush', () => {
  beforeEach(() => { vi.useFakeTimers(); });
  afterEach(() => { vi.useRealTimers(); });

  it('gives the moved report after 10 s when the worker does not answer', async () => {
    const { doc, client } = setup();
    const first = WITH_BIB;
    await typed(doc, first);
    const from = first.indexOf('[@a]');
    client.answer({ ...report(), citations: [{ from, to: from + 4, html: '(A)', markdown: '(A)', missing: [] }] });
    await settle();
    const edited = first.replace('Text', 'Some text');
    let done;
    doc.flush(edited).then((r) => { done = r; });
    await vi.advanceTimersByTimeAsync(9999);
    expect(done).toBe(undefined);
    await vi.advanceTimersByTimeAsync(1);
    expect(done.citations[0].html).toBe('(A)');
    expect(edited.slice(done.citations[0].from, done.citations[0].to)).toBe('[@a]');
  });

  it('gives null after 10 s with no earlier report', async () => {
    const { doc } = setup();
    let done;
    doc.flush(WITH_BIB).then((r) => { done = r; });
    await vi.advanceTimersByTimeAsync(10000);
    expect(done).toBe(null);
  });

  it('leaves no timer after an answer in time', async () => {
    const { doc, client } = setup();
    const flushed = doc.flush(WITH_BIB);
    await settle();
    client.answer(report());
    await flushed;
    await settle();
    expect(vi.getTimerCount()).toBe(0);
  });

  it('takes a late answer as the held report', async () => {
    const { doc, client } = setup();
    doc.flush(WITH_BIB);
    await vi.advanceTimersByTimeAsync(10000);
    const late = report('late');
    client.answer(late);
    await settle();
    expect(doc.reportFor(WITH_BIB)).toBe(late);
  });

  it('goes on with the next text after a late answer', async () => {
    const { doc, client } = setup();
    doc.flush(WITH_BIB);
    await vi.advanceTimersByTimeAsync(10000);
    await typed(doc, `${WITH_BIB}more`);
    client.answer(report());
    await settle();
    expect(client.asked).toEqual([WITH_BIB, `${WITH_BIB}more`]);
  });
});

describe('reset, when another document loads', () => {
  beforeEach(() => { vi.useFakeTimers(); });
  afterEach(() => { vi.useRealTimers(); });

  const chapterA = '---\nbibliography: refs.bib\n---\n\nChapter A [@a].\n';
  const chapterB = '---\nbibliography: refs.bib\n---\n\nChapter B [@a].\n';
  const reportOfA = () => {
    const from = chapterA.indexOf('[@a]');
    return {
      ...report('A'),
      citations: [{ from, to: from + 4, html: '(A)', markdown: '(A)', missing: [] }],
      bibliography: ['<div class="csl-entry">From A.</div>'],
    };
  };

  it('ignores a report of A that arrives after the load', async () => {
    const { doc, client, options } = setup();
    await typed(doc, chapterA);
    doc.reset();
    await typed(doc, chapterB);
    client.answer(reportOfA());
    await settle();
    expect(doc.current()).toBe(null);
    expect(doc.reportFor(chapterB)).toBe(null);
    expect(options.onChange).not.toHaveBeenCalled();
    expect(client.asked).toEqual([chapterA, chapterB]);
    const own = report('B');
    client.answer(own);
    await settle();
    expect(doc.reportFor(chapterB)).toBe(own);
    expect(options.onChange).toHaveBeenCalledTimes(1);
  });

  it('keeps B literal after the load, with no report of A', async () => {
    const { doc, client } = setup();
    await typed(doc, chapterA);
    client.answer(reportOfA());
    await settle();
    expect(doc.reportFor(chapterB)).not.toBe(null);
    doc.reset();
    expect(doc.reportFor(chapterB)).toBe(null);
    expect(doc.current()).toBe(null);
  });

  it('gives no report of A on the path of the flush limit', async () => {
    const { doc, client } = setup();
    await typed(doc, chapterA);
    client.answer(reportOfA());
    await settle();
    doc.reset();
    let done;
    doc.flush(chapterB).then((r) => { done = r; });
    await vi.advanceTimersByTimeAsync(10000);
    expect(done).toBe(null);
    expect(citationsLeftLiteral(chapterB, done)).toBe(true);
  });

  it('still answers a flush of A, and does not hold the report', async () => {
    const { doc, client } = setup();
    const flushed = doc.flush(chapterA);
    await settle();
    doc.reset();
    const own = reportOfA();
    client.answer(own);
    await expect(flushed).resolves.toBe(own);
    expect(doc.current()).toBe(null);
  });

  it('does not hold a report of a flush of A that waited behind another text', async () => {
    const { doc, client } = setup();
    await typed(doc, `${chapterA}typed`);
    const flushed = doc.flush(chapterA);
    doc.reset();
    client.answer(report('typed'));
    await settle();
    client.answer(reportOfA());
    await flushed;
    await settle();
    expect(doc.current()).toBe(null);
  });

  it('gives null to a flush of A past its limit after a load', async () => {
    const { doc, client } = setup();
    await typed(doc, `${chapterB}typed`);
    let done;
    doc.flush(chapterA).then((r) => { done = r; });
    doc.reset();
    await typed(doc, chapterB);
    client.answer(report('typed'));
    await settle();
    await vi.advanceTimersByTimeAsync(10000);
    expect(done).toBe(null);
  });

  it('drops a text that waits in the debounce', async () => {
    const { doc, client } = setup();
    doc.update(chapterA);
    doc.reset();
    await vi.advanceTimersByTimeAsync(300);
    expect(client.asked).toEqual([]);
  });
});

describe('refresh with a pending edit', () => {
  beforeEach(() => { vi.useFakeTimers(); });
  afterEach(() => { vi.useRealTimers(); });

  it('does not lose a text in the debounce, and reads the files for it', async () => {
    const { doc, client, options } = setup();
    await typed(doc, `${WITH_BIB}1`);
    client.answer(report());
    await settle();
    doc.update(`${WITH_BIB}2`);
    await vi.advanceTimersByTimeAsync(100);
    doc.refresh();
    await settle();
    expect(client.asked).toEqual([`${WITH_BIB}1`]);
    await vi.advanceTimersByTimeAsync(200);
    expect(client.asked).toEqual([`${WITH_BIB}1`, `${WITH_BIB}2`]);
    expect(options.listFiles).toHaveBeenCalledTimes(2);
    expect(client.setSources).toHaveBeenCalledTimes(2);
  });
});

describe('the held report', () => {
  beforeEach(() => { vi.useFakeTimers(); });
  afterEach(() => { vi.useRealTimers(); });

  it('does not go back to an older text', async () => {
    const older = `${WITH_BIB}older`;
    const newer = `${WITH_BIB}newer`;
    const { doc, client } = setup();
    await typed(doc, newer);
    const flushed = doc.flush(older);
    const kept = report('newer');
    client.answer(kept);
    await settle();
    await typed(doc, newer);
    const old = report('older');
    client.answer(old);
    await expect(flushed).resolves.toBe(old);
    await settle();
    expect(doc.current()).toEqual({ text: newer, report: kept });
  });
});

describe('metaPrefix', () => {
  const body = (n) => Array.from({ length: n }, (_, i) => `# line ${i}`);
  const document = (closingAt, eol = '\n') =>
    ['---', 'bibliography: refs.bib', ...body(closingAt - 2), '---', 'Text [@a].'].join(eol);

  it('is empty for a document with no frontmatter, at no cost for its size', () => {
    expect(metaPrefix(`Text\n${'x'.repeat(10_000_000)}`)).toBe('');
    expect(metaPrefix('')).toBe('');
    expect(metaPrefix('---text\n---\n')).toBe('');
  });

  it('stops at 50 lines in a long document', () => {
    const text = document(60);
    expect(metaPrefix(text).split('\n')).toHaveLength(51);
    expect(metaPrefix(text).length).toBeLessThan(text.length);
  });

  it.each(['\n', '\r\n', '\r'])('gives the same meta as the whole text at the limit, line end %j', (eol) => {
    for (const closingAt of [1, 2, 48, 49, 50, 51]) {
      const text = document(closingAt, eol);
      expect(readCitationMeta(metaPrefix(text))).toEqual(readCitationMeta(text));
    }
    expect(readCitationMeta(metaPrefix(document(49, eol))).bibliography).toEqual(['refs.bib']);
    expect(readCitationMeta(metaPrefix(document(50, eol))).bibliography).toEqual([]);
  });

  it('keeps a short document whole', () => {
    expect(metaPrefix(WITH_BIB)).toBe(WITH_BIB);
    expect(metaPrefix('---')).toBe('---');
  });
});

describe('citationsLeftLiteral', () => {
  const source = '---\nbibliography: r.bib\n---\n\nText [@a] and [@b].\n';
  const at = (slice) => {
    const from = source.indexOf(slice);
    return { from, to: from + slice.length, html: 'x', markdown: 'x', missing: [] };
  };

  it('is false with no bibliography, also with a citation in the text', () => {
    expect(citationsLeftLiteral('Text [@a].\n', null)).toBe(false);
  });
  it('is false when each citation has an output', () => {
    expect(citationsLeftLiteral(source, { ...report(), citations: [at('[@a]'), at('[@b]')] })).toBe(false);
  });
  it('is false for an unknown key, because the report has its output', () => {
    const missing = { ...at('[@b]'), missing: ['b'] };
    expect(citationsLeftLiteral(source, { ...report(), citations: [at('[@a]'), missing] })).toBe(false);
  });
  it('is true when a citation has no output', () => {
    expect(citationsLeftLiteral(source, { ...report(), citations: [at('[@a]')] })).toBe(true);
  });
  it('is true with no report', () => {
    expect(citationsLeftLiteral(source, null)).toBe(true);
  });
  it('is false for a document with a bibliography and no citations', () => {
    expect(citationsLeftLiteral('---\nbibliography: r.bib\n---\n\nNo keys.\n', null)).toBe(false);
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

describe('the library of the document', () => {
  it('is empty before a report and after a reset', async () => {
    const { client, doc } = setup();
    expect(doc.library()).toEqual([]);
    const flushed = doc.flush(WITH_BIB);
    await vi.waitFor(() => expect(client.update).toHaveBeenCalled());
    const entry = { key: 'a', authors: '', year: '', title: '', cited: true };
    client.answer({ ...report(), library: [entry] });
    await flushed;
    expect(doc.library()).toEqual([entry]);
    doc.reset();
    expect(doc.library()).toEqual([]);
  });
});

describe('documentMeta and documentUsesCitations', () => {
  it('reads the keys of the frontmatter', () => {
    expect(documentMeta(WITH_BIB).bibliography).toEqual(['refs.bib']);
    expect(documentMeta('# Title\n').bibliography).toEqual([]);
  });

  it('is true for a bibliography and for references', () => {
    expect(documentUsesCitations(WITH_BIB)).toBe(true);
    expect(documentUsesCitations('---\nreferences: [{"id": "a"}]\n---\n')).toBe(true);
    expect(documentUsesCitations('---\ncsl: apa\n---\n')).toBe(false);
    expect(documentUsesCitations('# Title\n')).toBe(false);
  });
});

describe('shareSource', () => {
  beforeEach(() => { vi.useFakeTimers(); });
  afterEach(() => { vi.useRealTimers(); });

  const answered = async (client, r = report()) => {
    await settle();
    client.answer(r);
    await settle();
  };

  it('loads nothing for a document with no citation keys', async () => {
    const { doc, options } = setup();
    await expect(doc.shareSource('# Plain\n')).resolves.toEqual({ text: '# Plain\n', failure: null, styleNote: null });
    expect(options.client).not.toHaveBeenCalled();
    expect(options.assets).not.toHaveBeenCalled();
    expect(options.listFiles).not.toHaveBeenCalled();
  });

  it('asks the worker after its sources are in', async () => {
    const { doc, client } = setup();
    const shared = doc.shareSource(WITH_BIB);
    await settle();
    expect(client.sources).toHaveLength(1);
    expect(client.shareSource).not.toHaveBeenCalled();
    await answered(client);
    expect(client.shareSource).toHaveBeenCalledWith(WITH_BIB);
    await expect(shared).resolves.toEqual({ text: `${WITH_BIB}shared`, failure: null, styleNote: null });
  });

  it('falls back to the plain text with a status at the limit', async () => {
    const { doc, client } = setup();
    const shared = doc.shareSource(WITH_BIB);
    await vi.advanceTimersByTimeAsync(10000);
    await expect(shared).resolves.toEqual({
      text: WITH_BIB, failure: 'The citations are not ready; the link has only the text', styleNote: null,
    });
    await answered(client);
    expect(client.update).toHaveBeenCalled();
  });

  it('falls back when the worker gives no text or no client loads', async () => {
    const { doc, client } = setup();
    client.shareSource = vi.fn(async () => null);
    const shared = doc.shareSource(WITH_BIB);
    await answered(client);
    await expect(shared).resolves.toMatchObject({ text: WITH_BIB, failure: expect.stringContaining('not ready') });
    const offline = setup({ client: vi.fn(async () => { throw new Error('offline'); }) });
    const late = offline.doc.shareSource(WITH_BIB);
    await settle();
    await expect(late).resolves.toMatchObject({ text: WITH_BIB, failure: expect.stringContaining('not ready') });
  });

  it('falls back when the sources cannot load', async () => {
    const { doc, client } = setup({ listFiles: vi.fn(async () => { throw new Error('storage'); }) });
    const shared = doc.shareSource(WITH_BIB);
    await answered(client);
    expect(client.shareSource).not.toHaveBeenCalled();
    await expect(shared).resolves.toMatchObject({ text: WITH_BIB, failure: expect.stringContaining('not ready') });
  });

  it('says when a style stays here', async () => {
    const { doc, client } = setup();
    const head = '---\nbibliography: refs.bib\ncsl: styles/mine.csl\n---\n\nText [@a].\n';
    client.shareSource = vi.fn(async (text) => text.replace('---\n\n', 'references: [{"id":"a"}]\n---\n\n'));
    const shared = doc.shareSource(head);
    await answered(client);
    await expect(shared).resolves.toMatchObject({
      failure: null,
      styleNote: 'The link carries the citations; the style mine.csl stays here, so the reader sees the default style.',
    });
  });

  it('gives a flush its report in the same run', async () => {
    const { doc, client } = setup();
    const flushed = doc.flush(WITH_BIB);
    const shared = doc.shareSource(WITH_BIB);
    const r = report('both');
    await answered(client, r);
    await expect(flushed).resolves.toBe(r);
    await expect(shared).resolves.toMatchObject({ text: `${WITH_BIB}shared` });
  });
});
