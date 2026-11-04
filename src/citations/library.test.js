import { describe, it, expect } from 'vitest';
import { resolveSources } from './library.js';

const DEP = '<style xmlns="http://purl.org/net/xbiblio/csl"><info><title>D</title><link href="http://www.zotero.org/styles/apa" rel="independent-parent"/></info></style>';
const OWN = '<style xmlns="http://purl.org/net/xbiblio/csl"><info><title>Own</title></info><citation><layout/></citation></style>';

const assets = {
  loadBundledStyle: async (id) => (['apa', 'chicago-author-date'].includes(id) ? `<bundled ${id}/>` : null),
  loadLocale: async (lang) => ({ lang: lang === 'pt' ? 'pt-PT' : 'en-US', xml: `<locale ${lang}/>` }),
};
const meta = (o = {}) => ({ bibliography: [], csl: null, lang: null, title: null, references: [], ...o });

describe('resolveSources', () => {
  it('uses chicago and en-US by default', async () => {
    const r = await resolveSources(meta(), [], assets);
    expect(r.styleXml).toBe('<bundled chicago-author-date/>');
    expect(r.lang).toBe('en-US');
    expect(r.fallbackLocaleXml).toBe('<locale en-US/>');
    expect(r.missing).toEqual([]);
  });
  it('matches bib files by base name, ignoring case', async () => {
    const files = [{ name: 'Refs.BIB', kind: 'bib', text: '@a{}' }];
    const r = await resolveSources(meta({ bibliography: ['refs.bib', 'x/refs', 'gone.bib'] }), files, assets);
    expect(r.bibs).toEqual([{ name: 'Refs.BIB', text: '@a{}' }]);
    expect(r.missing).toEqual(['gone.bib']);
  });
  it('finds the bundled style by id, with or without extension', async () => {
    expect((await resolveSources(meta({ csl: 'apa' }), [], assets)).styleXml).toBe('<bundled apa/>');
    expect((await resolveSources(meta({ csl: 'apa.csl' }), [], assets)).styleXml).toBe('<bundled apa/>');
  });
  it('prefers a stored style over the bundled one', async () => {
    const files = [{ name: 'apa.csl', kind: 'csl', text: OWN }];
    expect((await resolveSources(meta({ csl: 'styles/APA.csl' }), files, assets)).styleXml).toBe(OWN);
  });
  it('reports a missing style and falls back', async () => {
    const r = await resolveSources(meta({ csl: 'nope.csl' }), [], assets);
    expect(r.missing).toEqual(['nope.csl']);
    expect(r.styleXml).toBe('<bundled chicago-author-date/>');
    expect(r.styleError).toMatch(/chicago-author-date/);
  });
  it('names the parent of a dependent style', async () => {
    const files = [{ name: 'dep.csl', kind: 'csl', text: DEP.replace('/apa"', '/zzz"') }];
    const r = await resolveSources(meta({ csl: 'dep' }), files, assets);
    expect(r.styleError).toBe('This style depends on zzz. Add that file.');
    expect(r.styleXml).toBe('<bundled chicago-author-date/>');
  });
  it('uses the locale for lang', async () => {
    const r = await resolveSources(meta({ lang: 'pt' }), [], assets);
    expect(r.localeXml).toBe('<locale pt/>');
    expect(r.lang).toBe('pt-PT');
  });
  it('uses a stored parent of a dependent style', async () => {
    const files = [{ name: 'dep.csl', kind: 'csl', text: DEP }, { name: 'apa.csl', kind: 'csl', text: OWN }];
    const r = await resolveSources(meta({ csl: 'dep' }), files, assets);
    expect(r.styleXml).toBe(OWN);
    expect(r.styleError).toBeUndefined();
  });
  it('uses a bundled parent, with an alias', async () => {
    const dep = (id) => DEP.replace('styles/apa', 'styles/' + id).replace('http://www.zotero.org/styles/apa', 'http://www.zotero.org/styles/' + id);
    const a = { ...assets, loadBundledStyle: async (id) => (id === 'vancouver' || id === 'apa' ? `<b ${id}/>` : null) };
    expect((await resolveSources(meta({ csl: 'd' }), [{ name: 'd.csl', kind: 'csl', text: dep('apa') }], a)).styleXml).toBe('<b apa/>');
    const r = await resolveSources(meta({ csl: 'd' }), [{ name: 'd.csl', kind: 'csl', text: dep('nlm-citation-sequence') }], a);
    expect(r.styleXml).toBe('<b vancouver/>');
    expect(r.styleError).toBeUndefined();
  });
});
