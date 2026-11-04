import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { createEngine } from './engine.js';
import { checkStyle, localeFor, BUNDLED_STYLES, BUNDLED_LOCALES } from './style.js';

const style = (n) => readFileSync(new URL(`./styles/${n}.csl`, import.meta.url), 'utf8');
const locale = (l) => readFileSync(new URL(`./locales/locales-${l}.xml`, import.meta.url), 'utf8');

const items = [
  {
    id: 'jacome2020', type: 'article-journal', title: 'Mobile health tools',
    author: [{ family: 'Jácome', given: 'Cristina' }, { family: 'Almeida', given: 'Rute' }, { family: 'Pereira', given: 'Ana' }],
    issued: { 'date-parts': [[2020]] }, 'container-title': 'Journal of Tests', volume: '3', page: '1-10',
  },
  {
    id: 'smith2019', type: 'book', title: 'A book', author: [{ family: 'Smith', given: 'John' }],
    issued: { 'date-parts': [[2019]] }, publisher: 'Press',
  },
];
const cite = (keys, extra = {}) => ({
  from: 0, to: 1, bare: false,
  items: keys.map((key) => ({ key, prefix: '', suffix: '', locator: null, label: null, suppressAuthor: false })),
  ...extra,
});
const make = (s, lang = 'en-US', loc = lang) =>
  createEngine({ styleXml: style(s), localeXml: locale(loc), lang, items });

// citeproc is slow to start, and a loaded machine can take more than the default 5 s.
describe('createEngine', { timeout: 20000 }, () => {
  it('formats APA author-date', () => {
    const r = make('apa').render([cite(['jacome2020'])]);
    expect(r.texts[0]).toContain('Jácome et al., 2020');
    expect(r.bibliography.length).toBe(1);
  });
  it('gives a number in Vancouver', () => {
    const r = make('vancouver').render([cite(['jacome2020'])]);
    expect(r.texts[0]).toBe('(1)');
  });
  it('keeps prefix and locator', () => {
    const c = cite(['smith2019']);
    c.items[0].prefix = 'see';
    c.items[0].locator = '3';
    c.items[0].label = 'page';
    const t = make('apa').render([c]).texts[0];
    expect(t).toContain('see');
    expect(t).toMatch(/p\. 3/);
  });
  it('uses Portuguese terms in pt-PT', () => {
    const c = cite(['smith2019']);
    c.items[0].locator = '3';
    c.items[0].label = 'page';
    const t = make('apa', 'pt-PT').render([c]).texts[0];
    expect(t).toMatch(/p\. 3/);
    const b = make('apa', 'pt-PT').render([cite(['jacome2020'])]);
    expect(b.texts[0]).toContain('et al.');
    expect(b.bibliography[0]).toMatch(/\(?2020\)?/);
    const ch = cite(['smith2019']);
    ch.items[0].locator = '3';
    ch.items[0].label = 'chapter';
    expect(make('apa', 'en-US').render([ch]).texts[0]).toMatch(/Chapter 3/);
    expect(make('apa', 'pt-PT').render([ch]).texts[0]).toMatch(/Cap[ií]tulo 3/i);
  });
  it('leaves out an unknown key and renders the others', () => {
    const r = make('apa').render([cite(['nope', 'smith2019'])]);
    expect(r.texts[0]).toContain('Smith');
    expect(r.texts[0]).not.toContain('nope');
  });
  it('gives an empty text only for unknown keys', () => {
    const r = make('apa').render([cite(['nope']), cite(['smith2019'])]);
    expect(r.texts[0]).toBe('');
    expect(r.texts[1]).toContain('Smith');
  });
  it('gives equal output on two calls', () => {
    const e = make('apa');
    const cs = [cite(['smith2019']), cite(['jacome2020', 'smith2019'])];
    const a = e.render(cs);
    const b = e.render(cs);
    expect(b).toEqual(a);
    const n = make('vancouver');
    const x = n.render([cite(['smith2019']), cite(['jacome2020'])]);
    expect(n.render([cite(['smith2019']), cite(['jacome2020'])])).toEqual(x);
  });
  it('follows a changed citation list', () => {
    const e = make('vancouver');
    e.render([cite(['smith2019']), cite(['jacome2020'])]);
    const r = e.render([cite(['jacome2020'])]);
    expect(r.bibliography.length).toBe(1);
    expect(r.bibliography[0]).toContain('Jácome');
  });
  it('joins author-only and suppress-author for bare citations', () => {
    const r = make('apa').render([cite(['jacome2020'], { bare: true })]);
    expect(r.texts[0]).toMatch(/Jácome et al\.\s*\(2020\)/);
  });
  it('returns empty output for no citations', () => {
    expect(make('apa').render([])).toEqual({ texts: [], bibliography: [] });
  });
});

describe('createEngine errors and bare numeric', { timeout: 20000 }, () => {
  const opts = (styleXml) => ({ styleXml, localeXml: locale('en-US'), lang: 'en-US', items });
  it('throws a clear error for a truncated style', () => {
    const xml = style('apa').slice(0, 3000);
    expect(() => createEngine(opts(xml))).toThrow(/not valid/i);
  });
  it('throws a clear error for text that is not a style', () => {
    expect(() => createEngine(opts('hello'))).toThrow(/not valid/i);
  });
  it('throws and names the parent for a dependent style', () => {
    const xml = `<?xml version="1.0"?><style xmlns="http://purl.org/net/xbiblio/csl" version="1.0"><info><title>Dep</title><id>http://x/dep</id>
<link href="http://www.zotero.org/styles/ieee" rel="independent-parent"/></info></style>`;
    expect(() => createEngine(opts(xml))).toThrow(/ieee/);
  });
  it('gives no NO_PRINTED_FORM for bare citations in numeric styles', () => {
    for (const n of ['ieee', 'vancouver']) {
      const t = make(n).render([cite(['jacome2020'], { bare: true })]).texts[0];
      expect(t).not.toContain('NO_PRINTED_FORM');
      expect(t).toMatch(/1/);
    }
  });
  it('uses the fallback locale for a term missing in the main one', () => {
    const e = createEngine({ ...opts(style('apa')), lang: 'pt-PT', localeXml: locale('pt-PT'), fallbackLocaleXml: locale('en-US') });
    expect(e.render([cite(['smith2019'])]).texts[0]).toContain('Smith');
  });
});

describe('checkStyle', () => {
  it('reports invalid for a truncated style', () => {
    expect(checkStyle(style('apa').slice(0, 3000))).toEqual({ ok: false, reason: 'invalid' });
  });
  it('reports invalid for a style without citation', () => {
    expect(checkStyle('<style xmlns="x"><info><title>T</title></info></style>')).toEqual({ ok: false, reason: 'invalid' });
  });
  it('accepts a bundled style', () => {
    const r = checkStyle(style('apa'));
    expect(r.ok).toBe(true);
    expect(r.title).toMatch(/APA/);
  });
  it('reports a dependent style with its parent', () => {
    const xml = `<?xml version="1.0"?><style xmlns="http://purl.org/net/xbiblio/csl" version="1.0"><info><title>Dep</title><id>http://x/dep</id>
<link href="http://www.zotero.org/styles/dep" rel="self"/>
<link href="http://www.zotero.org/styles/american-medical-association" rel="independent-parent"/></info></style>`;
    expect(checkStyle(xml)).toEqual({ ok: false, reason: 'dependent', parent: 'american-medical-association' });
  });
  it('reports invalid for text that is not XML', () => {
    expect(checkStyle('hello')).toEqual({ ok: false, reason: 'invalid' });
    expect(checkStyle('')).toEqual({ ok: false, reason: 'invalid' });
  });
});

describe('style lists', () => {
  it('lists five styles and four locales', () => {
    expect(BUNDLED_STYLES.map((s) => s.id)).toEqual(['chicago-author-date', 'apa', 'vancouver', 'american-medical-association', 'ieee']);
    expect(BUNDLED_LOCALES).toEqual(['en-US', 'en-GB', 'pt-PT', 'es-ES']);
  });
  it('falls back by language prefix', () => {
    expect(localeFor('pt-BR')).toBe('pt-PT');
    expect(localeFor('es-MX')).toBe('es-ES');
    expect(localeFor('en-AU')).toBe('en-GB');
    expect(localeFor('pt')).toBe('pt-PT');
    expect(localeFor('fr')).toBe('en-US');
    expect(localeFor(undefined)).toBe('en-US');
    expect(localeFor('pt-PT')).toBe('pt-PT');
  });
});
