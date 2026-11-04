import { describe, it, expect, vi } from 'vitest';
import { readFileSync } from 'node:fs';
import { createSession } from './session.js';
import { createEngine } from './engine.js';

const style = (n) => readFileSync(new URL(`./styles/${n}.csl`, import.meta.url), 'utf8');
const locale = (l) => readFileSync(new URL(`./locales/locales-${l}.xml`, import.meta.url), 'utf8');

const BIB = `@article{jacome2020,
  author = {Jácome, Cristina and Almeida, Rute},
  title = {Mobile health tools},
  journal = {Journal of Tests},
  year = {2020},
  doi = {10.1000/xyz}
}
@book{smith2019,
  author = {Smith, John},
  title = {A book},
  publisher = {Press},
  year = {2019}
}
@misc{unused2001,
  title = {Never cited},
  year = {2001}
}
@misc{badurl,
  author = {Bad, Url},
  title = {A title with <script>alert(1)</script> inside},
  url = {javascript:alert(1)},
  year = {2021}
}
`;
const sources = (extra = {}) => ({
  bibs: [{ name: 'refs.bib', text: BIB }], styleXml: style('apa'), localeXml: locale('en-US'), lang: 'en-US', ...extra,
});
const doc = (body, head = 'bibliography: refs.bib') => `---\n${head}\n---\n${body}`;
const ready = (extra) => { const s = createSession(); s.setSources(sources(extra)); return s; };
const fileNotes = (r) => r.notes.filter((n) => 'file' in n);

describe('analyse: scope', () => {
  it('gives an empty report with no bibliography and no references', () => {
    const s = ready();
    const src = 'A [@jacome2020] b\n';
    expect(s.analyse(src)).toEqual({
      citations: [], bibliography: [], bibliographyMarkdown: '', library: [], notes: [], markdownSource: src,
    });
  });
  it('does not scan or build an engine for such a document', () => {
    const makeEngine = vi.fn();
    const s = createSession({ makeEngine });
    s.setSources(sources());
    s.analyse('[@jacome2020]');
    expect(makeEngine).not.toHaveBeenCalled();
  });
  it('gives the library and no bibliography with no citations', () => {
    const r = ready().analyse(doc('No citations.\n'));
    expect(r.citations).toEqual([]);
    expect(r.bibliography).toEqual([]);
    expect(r.library.length).toBe(4);
    expect(r.markdownSource).toBe(doc('No citations.\n'));
  });
});

describe('analyse: citations', () => {
  const src = doc('One [@jacome2020] two [@smith2019] three [@nokey] end.\nLast line');
  it('reports two citations and one unknown key', () => {
    const r = ready().analyse(src);
    expect(r.citations.length).toBe(3);
    expect(r.citations[0].html).toContain('Jácome');
    expect(r.citations[0].missing).toEqual([]);
    expect(r.citations[0].from).toBe(src.indexOf('[@jacome2020]'));
    expect(r.citations[2].html).toBe('[@nokey]');
    expect(r.citations[2].markdown).toBe('[@nokey]');
    expect(r.citations[2].missing).toEqual(['nokey']);
    expect(r.bibliography.length).toBe(2);
  });
  it('gives a note with the range of an unknown key', () => {
    const r = ready().analyse(src);
    const from = src.indexOf('[@nokey]');
    expect(r.notes).toEqual([{ from, to: from + 8, message: 'No entry called nokey.' }]);
  });
  it('formats the known keys of a mixed citation and lists the others', () => {
    const r = ready().analyse(doc('[@smith2019; @nokey; @nokey]'));
    expect(r.citations[0].html).toContain('Smith');
    expect(r.citations[0].html).not.toContain('nokey');
    expect(r.citations[0].missing).toEqual(['nokey']);
    expect(r.notes.length).toBe(1);
  });
  it('escapes the source text of an all-unknown citation', () => {
    const r = ready().analyse(doc('[<b> @nokey]'));
    expect(r.citations[0].html).toBe('[&lt;b&gt; @nokey]');
    expect(r.citations[0].markdown).toBe('[<b> @nokey]');
  });
  it('keeps the line count of the source up to its last line', () => {
    const multi = doc('One [@jacome2020;\n@smith2019] two\nLast line');
    const r = ready().analyse(multi);
    const inLines = multi.split('\n');
    const outLines = r.markdownSource.split('\n');
    expect(outLines[inLines.length - 1]).toBe('Last line');
    expect(outLines[inLines.length]).toBe('');
    expect(outLines.length).toBeGreaterThan(inLines.length + 1);
  });
  it('adds the reference title and the entries to markdownSource', () => {
    const r = ready().analyse(doc('[@jacome2020]\n', 'bibliography: refs.bib\nreference-section-title: Referências'));
    expect(r.markdownSource).toContain('\n\n## Referências\n\nJácome, C., ');
    expect(r.bibliographyMarkdown).toContain('*Journal of Tests*');
    expect(r.bibliographyMarkdown).toContain('https://doi.org/10.1000/xyz');
  });
  it('separates entries with a blank line', () => {
    const r = ready().analyse(doc('[@jacome2020] [@smith2019]'));
    expect(r.bibliographyMarkdown.split('\n\n').length).toBe(2);
  });
  it('writes numbered entries as paragraphs', () => {
    const r = ready({ styleXml: style('vancouver') }).analyse(doc('[@jacome2020] [@smith2019]'));
    const [first, second] = r.bibliographyMarkdown.split('\n\n');
    expect(first).toMatch(/^1\\\. Jácome C/);
    expect(second).toMatch(/^2\\\. Smith J/);
    expect(r.bibliography[0]).toContain('csl-left-margin');
  });
  it('writes a superscript citation style', () => {
    const r = ready({ styleXml: style('american-medical-association') }).analyse(doc('Text[@jacome2020].'));
    expect(r.citations[0].html).toBe('<sup>1</sup>');
    expect(r.citations[0].markdown).toBe('¹');
  });
  it('gives no anchor for javascript: in a bib url', () => {
    const r = ready().analyse(doc('[@badurl]'));
    expect(r.bibliography[0]).not.toContain('<a');
    expect(r.bibliography[0]).toContain('javascript:alert(1)');
  });
  it('keeps <script> in a title as text', () => {
    const r = ready().analyse(doc('[@badurl]'));
    expect(r.bibliography[0]).not.toContain('<script');
    expect(r.bibliography[0]).toMatch(/&#60;script&#62;|&lt;script&gt;/);
    expect(r.bibliographyMarkdown).toContain('\\<script>');
  });
  it('turns <i> into *', () => {
    const r = ready().analyse(doc('[@smith2019]'));
    expect(r.bibliography[0]).toContain('<i>A book</i>');
    expect(r.bibliographyMarkdown).toContain('*A book*');
  });
  it('trims the bibliography strings', () => {
    const r = ready().analyse(doc('[@smith2019]'));
    expect(r.bibliography[0]).toMatch(/^<div class="csl-entry">.*<\/div>$/);
  });
});

describe('analyse: library', () => {
  it('lists entries by key and marks the cited ones', () => {
    const r = ready().analyse(doc('[@smith2019] [@nokey]'));
    expect(r.library.map((e) => e.key)).toEqual(['badurl', 'jacome2020', 'smith2019', 'unused2001']);
    expect(r.library.find((e) => e.key === 'smith2019')).toEqual({
      key: 'smith2019', authors: 'Smith', year: '2019', title: 'A book', cited: true,
    });
    expect(r.library.find((e) => e.key === 'jacome2020')).toMatchObject({ authors: 'Jácome, Almeida', cited: false });
  });
  it('adds the references entries', () => {
    const r = ready().analyse(doc('[@ref1]', 'bibliography: refs.bib\nreferences: [{"id":"ref1","type":"book","title":"Inline","author":[{"family":"Ines"}],"issued":{"date-parts":[[1999]]}}]'));
    expect(r.citations[0].html).toContain('Ines');
    expect(r.library.find((e) => e.key === 'ref1')).toEqual({ key: 'ref1', authors: 'Ines', year: '1999', title: 'Inline', cited: true });
  });
  it('works with references and no bibliography key', () => {
    const r = ready({ bibs: [] }).analyse(doc('[@ref1]', 'references: [{"id":"ref1","type":"book","title":"Inline"}]'));
    expect(r.citations[0].missing).toEqual([]);
    expect(r.library.length).toBe(1);
  });
  it('lets a bib entry win over a references entry with the same key', () => {
    const r = ready().analyse(doc('[@smith2019]', 'bibliography: refs.bib\nreferences: [{"id":"smith2019","type":"book","title":"Other"}]'));
    expect(r.library.filter((e) => e.key === 'smith2019').map((e) => e.title)).toEqual(['A book']);
    expect(r.bibliography[0]).toContain('A book');
  });
  it('does not fail on odd field shapes in a references entry', () => {
    const r = ready({ bibs: [] }).analyse(doc('text', 'references: [{"id":"x","title":5,"author":"Smith","issued":"2020"}]'));
    expect(r.library).toEqual([{ key: 'x', authors: '', year: '', title: '', cited: false }]);
  });
  it('reads authors that have a literal name', () => {
    const r = ready({ bibs: [] }).analyse(doc('t', 'references: [{"id":"x","author":[{"literal":"WHO"},{"family":"Smith"},5]}]'));
    expect(r.library[0].authors).toBe('WHO, Smith');
  });
});

describe('analyse: sources not ready or a style error', () => {
  const src = doc('A [@smith2019] b [@nokey].\n');
  const literal = (r) => {
    expect(r.citations.map((c) => c.markdown)).toEqual(['[@smith2019]', '[@nokey]']);
    expect(r.citations.map((c) => c.missing)).toEqual([[], []]);
    expect(r.bibliography).toEqual([]);
    expect(r.bibliographyMarkdown).toBe('');
    expect(r.markdownSource).toBe(src);
    expect(r.notes.length).toBe(1);
    expect(r.notes[0]).toMatchObject({ from: 0, to: 0, line: 0 });
  };
  it('stays literal before any sources arrive', () => {
    const r = createSession().analyse(src);
    literal(r);
    expect(r.library).toEqual([]);
  });
  it('stays literal with no style and keeps the library', () => {
    const r = ready({ styleXml: null }).analyse(src);
    literal(r);
    expect(r.library.length).toBe(4);
  });
  it('reports a dependent style with its parent', () => {
    const xml = `<?xml version="1.0"?><style xmlns="http://purl.org/net/xbiblio/csl" version="1.0"><info><title>Dep</title>
<link href="http://www.zotero.org/styles/apa" rel="independent-parent"/></info></style>`;
    const r = ready({ styleXml: xml }).analyse(doc('[@smith2019]', 'bibliography: refs.bib\ncsl: dep.csl'));
    expect(r.notes).toEqual([{ from: 0, to: 0, file: 'dep.csl', line: 0, message: 'This style depends on apa. Add that file.' }]);
    expect(r.library.length).toBe(4);
  });
  it('reports an invalid style', () => {
    const r = ready({ styleXml: 'hello' }).analyse(src);
    literal(r);
    expect(r.notes[0].message).toBe('The style file is not valid CSL.');
  });
  it('uses a styleError from the sources', () => {
    const r = ready({ styleError: 'This style depends on x. Add that file.' }).analyse(src);
    literal(r);
    expect(r.notes[0].message).toBe('This style depends on x. Add that file.');
  });
  it('turns an engine error into a file note and stays alive', () => {
    const s = createSession({ makeEngine: () => { throw new Error('The style file cannot be used: bad'); } });
    s.setSources(sources());
    const r = s.analyse(src);
    literal(r);
    expect(r.notes[0].message).toBe('The style file cannot be used: bad');
    expect(s.analyse(src).notes.length).toBe(1);
  });
  it('turns a render error into a note', () => {
    const s = createSession({ makeEngine: () => ({ render() { throw new Error('boom'); } }) });
    s.setSources(sources());
    literal(s.analyse(src));
  });
  it('names a references entry that citeproc rejects', () => {
    const head = 'bibliography: refs.bib\nreferences: [{"id":"odd","type":"book","author":[1,2],"title":"T"}]';
    const s = ready();
    const r = s.analyse(doc('[@smith2019] [@odd]', head));
    expect(r.citations.map((c) => c.markdown)).toEqual(['[@smith2019]', '[@odd]']);
    expect(r.notes).toEqual([{ from: 0, to: 0, file: '', line: 0, message: 'Entry odd cannot be formatted.' }]);
    expect(r.library.length).toBe(5);
    // The next document text works again.
    expect(s.analyse(doc('[@smith2019]', head)).citations[0].html).toContain('Smith');
  });
});

describe('analyse: file notes', () => {
  it('passes bib notes with the file and the line', () => {
    const bad = `${BIB}@misc{broken,\n  title = {x\n`;
    const r = ready({ bibs: [{ name: 'refs.bib', text: bad }] }).analyse(doc('[@smith2019]'));
    expect(fileNotes(r).length).toBe(1);
    expect(fileNotes(r)[0]).toMatchObject({ from: 0, to: 0, file: 'refs.bib' });
    expect(fileNotes(r)[0].line).toBeGreaterThan(0);
    expect(fileNotes(r)[0].message).toContain('broken');
    expect(r.citations[0].html).toContain('Smith');
  });
  it('reports a missing file', () => {
    const r = ready({ bibs: [], missing: ['refs.bib'] }).analyse(doc('text'));
    expect(r.notes).toEqual([{ from: 0, to: 0, file: 'refs.bib', line: 0, message: 'The file refs.bib is missing.' }]);
  });
  it('gives one note for a missing style file', () => {
    const r = ready({ styleXml: null, missing: ['my.csl'] }).analyse(doc('[@smith2019]'));
    expect(r.notes).toEqual([{ from: 0, to: 0, file: 'my.csl', line: 0, message: 'The file my.csl is missing.' }]);
  });
});

describe('cache', () => {
  const spying = () => {
    const renders = vi.fn();
    const makeEngine = vi.fn((options) => {
      const engine = createEngine(options);
      return { render(c) { renders(); return engine.render(c); } };
    });
    return { renders, makeEngine, session: createSession({ makeEngine }) };
  };
  it('does not render again when only the prose changes', () => {
    const { renders, makeEngine, session } = spying();
    session.setSources(sources());
    const a = session.analyse(doc('A [@smith2019] [@nokey].'));
    const moved = doc('Some new prose. A [@smith2019] [@nokey].');
    const b = session.analyse(moved);
    expect(renders).toHaveBeenCalledTimes(1);
    expect(makeEngine).toHaveBeenCalledTimes(1);
    expect(b.citations[0].from).toBe(moved.indexOf('[@smith2019]'));
    expect(b.citations[0].from).not.toBe(a.citations[0].from);
    expect(b.citations[0].html).toBe(a.citations[0].html);
    expect(b.notes[0].from).toBe(moved.indexOf('[@nokey]'));
    expect(b.markdownSource).toContain('Some new prose.');
  });
  it('renders again when a citation changes', () => {
    const { renders, makeEngine, session } = spying();
    session.setSources(sources());
    session.analyse(doc('[@smith2019]'));
    session.analyse(doc('[@smith2019, p. 3]'));
    session.analyse(doc('[see @smith2019, p. 3]'));
    session.analyse(doc('[@smith2019, p. 3] and more [see @smith2019, p. 3]'));
    session.analyse(doc('@smith2019'));
    session.analyse(doc('[-@smith2019]'));
    expect(renders).toHaveBeenCalledTimes(6);
    expect(makeEngine).toHaveBeenCalledTimes(1);
  });
  it('does not build an engine again for equal sources', () => {
    const { makeEngine, renders, session } = spying();
    session.setSources(sources());
    session.analyse(doc('[@smith2019]'));
    session.setSources(sources());
    session.analyse(doc('[@smith2019]'));
    expect(makeEngine).toHaveBeenCalledTimes(1);
    expect(renders).toHaveBeenCalledTimes(1);
  });
  it('builds a new engine when style, locale or lang change', () => {
    const { makeEngine, session } = spying();
    session.setSources(sources());
    session.analyse(doc('[@smith2019]'));
    session.setSources(sources({ styleXml: style('vancouver') }));
    expect(session.analyse(doc('[@smith2019]')).citations[0].html).toBe('(1)');
    session.setSources(sources({ styleXml: style('vancouver'), localeXml: locale('pt-PT'), lang: 'pt-PT' }));
    session.analyse(doc('[@smith2019]'));
    expect(makeEngine).toHaveBeenCalledTimes(3);
  });
  it('builds a new engine when the items change', () => {
    const { makeEngine, session } = spying();
    session.setSources(sources());
    const head = (t) => `bibliography: refs.bib\nreferences: [{"id":"r","type":"book","title":"${t}"}]`;
    session.analyse(doc('[@r]', head('One')));
    session.analyse(doc('[@r] more', head('One')));
    expect(makeEngine).toHaveBeenCalledTimes(1);
    expect(session.analyse(doc('[@r]', head('Two'))).bibliography[0]).toContain('Two');
    expect(makeEngine).toHaveBeenCalledTimes(2);
    session.setSources(sources({ bibs: [] }));
    session.analyse(doc('[@r]', head('Two')));
    expect(makeEngine).toHaveBeenCalledTimes(3);
  });
  it('does not retry a failed engine on each analyse', () => {
    const makeEngine = vi.fn(() => { throw new Error('bad'); });
    const s = createSession({ makeEngine });
    s.setSources(sources());
    s.analyse(doc('[@smith2019]'));
    s.analyse(doc('more [@smith2019]'));
    expect(makeEngine).toHaveBeenCalledTimes(1);
  });
  it('builds no engine when no citation has a known key', () => {
    const { makeEngine, session } = spying();
    session.setSources(sources());
    session.analyse(doc('[@nokey]'));
    expect(makeEngine).not.toHaveBeenCalled();
  });
});

describe('locales', () => {
  it('passes the fallback locale to the engine', () => {
    const makeEngine = vi.fn(() => ({ render: () => ({ texts: ['x'], bibliography: [] }) }));
    const s = createSession({ makeEngine });
    s.setSources(sources({ localeXml: locale('pt-PT'), fallbackLocaleXml: locale('en-US'), lang: 'pt-PT' }));
    s.analyse(doc('[@smith2019]'));
    expect(makeEngine).toHaveBeenCalledWith(expect.objectContaining({
      lang: 'pt-PT', localeXml: locale('pt-PT'), fallbackLocaleXml: locale('en-US'),
    }));
  });
  it('formats in pt-PT with the real engine', () => {
    const s = ready({ localeXml: locale('pt-PT'), fallbackLocaleXml: locale('en-US'), lang: 'pt-PT' });
    const r = s.analyse(doc('[@smith2019, chap. 3]'));
    expect(r.citations[0].html).toMatch(/Cap[ií]tulo 3/i);
  });
});
