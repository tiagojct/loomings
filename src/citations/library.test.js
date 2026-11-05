import { describe, it, expect } from 'vitest';
import { planNativeSources, resolveSources } from './library.js';

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
  it('keeps the first file for two entries with one base name', async () => {
    const files = [{ name: 'a/refs.bib', kind: 'bib', text: '@a{}' }, { name: 'b/refs.bib', kind: 'bib', text: '@b{}' }];
    const r = await resolveSources(meta({ bibliography: ['a/refs.bib', 'b/refs.bib'] }), files, assets);
    expect(r.bibs).toEqual([{ name: 'a/refs.bib', text: '@a{}' }]);
    expect(r.missing).toEqual([]);
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
    expect(r.styleNote).toMatch(/chicago-author-date/);
    expect(r.styleError).toBeUndefined();
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

describe('a parent with the name of an Object method', () => {
  it('finds no alias on the prototype', async () => {
    const xml = DEP.replace('styles/apa', 'styles/constructor').replace('http://www.zotero.org/styles/apa', 'http://www.zotero.org/styles/constructor');
    const r = await resolveSources(meta({ csl: 'd' }), [{ name: 'd.csl', kind: 'csl', text: xml }], assets);
    expect(r.styleError).toBe('This style depends on constructor. Add that file.');
  });
});

describe('planNativeSources', () => {
  const nlm = DEP.replace('styles/apa', 'styles/nlm-citation-sequence');

  it('asks for each bibliography as it is written, and needs no style file by default', () => {
    const plan = planNativeSources(meta({ bibliography: ['refs.bib', '/abs/other.bib'] }), {});
    expect(plan).toMatchObject({ bibFiles: ['refs.bib', '/abs/other.bib'], stylePath: null, styleId: 'chicago-author-date' });
    expect(plan).toMatchObject({ lang: 'en-US', fallbackLang: 'en-US', done: false });
  });
  it('is done when the files are read, and lists only the files in use', () => {
    const plan = planNativeSources(meta({ bibliography: ['refs.bib'] }), { files: [{ name: 'refs.bib', kind: 'bib' }], tried: ['refs.bib'] });
    expect(plan).toMatchObject({ bibFiles: ['refs.bib'], missing: [], done: true });
  });
  it('adds the .bib ending to a name with none', () => {
    expect(planNativeSources(meta({ bibliography: ['x/refs'] }), {}).bibFiles).toEqual(['x/refs.bib']);
  });
  it('keeps two files with one base name, because it reads by path', () => {
    const files = [{ name: 'a/refs.bib', kind: 'bib' }, { name: 'b/refs.bib', kind: 'bib' }];
    const plan = planNativeSources(meta({ bibliography: ['a/refs.bib', 'b/refs.bib'] }), { files, tried: ['a/refs.bib', 'b/refs.bib'] });
    expect(plan).toMatchObject({ bibFiles: ['a/refs.bib', 'b/refs.bib'], missing: [], done: true });
  });
  it('asks for each path when the names share a base name', () => {
    expect(planNativeSources(meta({ bibliography: ['a/refs.bib', 'b/refs.bib'] }), {}).bibFiles).toEqual(['a/refs.bib', 'b/refs.bib']);
  });
  it('gives a note for a path that is absent, also when another file has its base name', () => {
    const files = [{ name: 'a/refs.bib', kind: 'bib' }];
    const plan = planNativeSources(meta({ bibliography: ['a/refs.bib', 'b/refs.bib'] }), { files, tried: ['a/refs.bib', 'b/refs.bib'] });
    expect(plan).toMatchObject({ bibFiles: ['a/refs.bib'], missing: ['b/refs.bib'], done: true });
  });
  it('lists one file once when a path is written twice', () => {
    const files = [{ name: 'refs.bib', kind: 'bib' }];
    expect(planNativeSources(meta({ bibliography: ['refs.bib', 'refs.bib'] }), { files, tried: ['refs.bib'] }).bibFiles).toEqual(['refs.bib']);
  });
  it('finds a style by its path, not by a file with the same base name', () => {
    const other = { name: 'old/own.csl', kind: 'csl', text: OWN };
    const plan = planNativeSources(meta({ csl: 'new/own.csl' }), { files: [other], tried: ['old/own.csl'] });
    expect(plan).toMatchObject({ stylePath: 'new/own.csl', done: false });
  });
  it('moves a file that could not be read to missing', () => {
    const plan = planNativeSources(meta({ bibliography: ['gone.bib'] }), { tried: ['gone.bib'] });
    expect(plan).toMatchObject({ bibFiles: [], missing: ['gone.bib'], done: true });
    expect(plan.missingNotes).toEqual({});
  });
  it('tries a style file first, as the web prefers a stored style', () => {
    const plan = planNativeSources(meta({ csl: 'apa' }), {});
    expect(plan).toMatchObject({ stylePath: 'apa.csl', styleId: null, done: false });
    const next = planNativeSources(meta({ csl: 'apa' }), { tried: ['apa.csl'] });
    expect(next).toMatchObject({ stylePath: null, styleId: 'apa', done: true });
    expect(next.styleError).toBeUndefined();
  });
  it('uses a style file that is valid', () => {
    const plan = planNativeSources(meta({ csl: 'styles/own.csl' }), { files: [{ name: 'styles/own.csl', kind: 'csl', text: OWN }], tried: ['styles/own.csl'] });
    expect(plan).toMatchObject({ stylePath: 'styles/own.csl', styleId: null, done: true });
  });
  it('reports a style that is not found, and falls back to the default', () => {
    const plan = planNativeSources(meta({ csl: 'nope.csl' }), { tried: ['nope.csl'] });
    expect(plan).toMatchObject({ stylePath: null, styleId: 'chicago-author-date', missing: ['nope.csl'], done: true });
    expect(plan.styleNote).toMatch(/chicago-author-date/);
    expect(plan.styleError).toBeUndefined();
  });
  it('reads the parent of a dependent style from the same folder, then uses it', () => {
    const dep = { name: 'csl/dep.csl', kind: 'csl', text: DEP.replace('/apa"', '/own"') };
    const first = planNativeSources(meta({ csl: 'csl/dep.csl' }), { files: [dep], tried: ['csl/dep.csl'] });
    expect(first).toMatchObject({ stylePath: 'csl/own.csl', done: false });
    const parent = { name: 'csl/own.csl', kind: 'csl', text: OWN };
    const next = planNativeSources(meta({ csl: 'csl/dep.csl' }), { files: [dep, parent], tried: ['csl/dep.csl', 'csl/own.csl'] });
    expect(next).toMatchObject({ stylePath: 'csl/own.csl', styleId: null, done: true });
    expect(next.styleError).toBeUndefined();
  });
  it('falls to a bundled parent through the alias', () => {
    const dep = { name: 'dep.csl', kind: 'csl', text: nlm };
    const plan = planNativeSources(meta({ csl: 'dep.csl' }), { files: [dep], tried: ['dep.csl', 'nlm-citation-sequence.csl'] });
    expect(plan).toMatchObject({ stylePath: null, styleId: 'vancouver', done: true });
    expect(plan.styleError).toBeUndefined();
  });
  it('names a parent that cannot be found', () => {
    const dep = { name: 'dep.csl', kind: 'csl', text: DEP.replace('/apa"', '/zzz"') };
    const plan = planNativeSources(meta({ csl: 'dep.csl' }), { files: [dep], tried: ['dep.csl', 'zzz.csl'] });
    expect(plan.styleError).toBe('This style depends on zzz. Add that file.');
    expect(plan).toMatchObject({ styleId: 'chicago-author-date', done: true });
  });
  it('rejects a style file that is not CSL', () => {
    const bad = { name: 'bad.csl', kind: 'csl', text: 'not xml' };
    const plan = planNativeSources(meta({ csl: 'bad.csl' }), { files: [bad], tried: ['bad.csl'] });
    expect(plan.styleError).toBe('The style file is not valid CSL.');
    expect(plan).toMatchObject({ stylePath: null, styleId: 'chicago-author-date', done: true });
  });
  it('chooses the locale with the web rule', () => {
    expect(planNativeSources(meta({ lang: 'pt' }), {})).toMatchObject({ lang: 'pt-PT', fallbackLang: 'en-US' });
    expect(planNativeSources(meta({ lang: 'en-AU' }), {}).lang).toBe('en-GB');
  });
  it('explains a relative name in a document with no folder', () => {
    const entries = ['refs.bib', '/abs/gone.bib', '~/gone.bib'];
    const plan = planNativeSources(meta({ bibliography: entries }), { tried: entries, noFolder: true });
    expect(plan.missing).toEqual(entries);
    expect(Object.keys(plan.missingNotes)).toEqual(['refs.bib']);
    expect(plan.missingNotes['refs.bib']).toMatch(/no folder/);
  });
  it('says when a file exists but cannot be read as text', () => {
    const plan = planNativeSources(meta({ bibliography: ['latin.bib'] }), { tried: ['latin.bib'], unreadable: ['latin.bib'] });
    expect(plan.missingNotes['latin.bib']).toBe('The file latin.bib could not be read as text.');
  });
});

describe('planNativeSources: allowPaths', () => {
  const closed = { allowPaths: false, noFolder: true };

  it('does not ask for an absolute or a parent path', () => {
    const entries = ['/Users/me/a.bib', '~/b.bib', '../c.bib', 'd/../../e.bib', 'C:\\f.bib'];
    const plan = planNativeSources({ bibliography: entries, csl: '/Users/me/s.csl' }, closed);
    expect(plan).toMatchObject({
      bibFiles: [], stylePath: null, styleId: 'chicago-author-date', missing: [], done: true,
      ignoredPaths: [...entries, '/Users/me/s.csl'],
    });
    expect(plan.styleNote).toBeUndefined();
  });
  it('still asks for a name in the folder', () => {
    const plan = planNativeSources({ bibliography: ['refs.bib', 'a/b.bib', 'a..b.bib'], csl: 'apa' }, closed);
    expect(plan).toMatchObject({ bibFiles: ['refs.bib', 'a/b.bib', 'a..b.bib'], stylePath: 'apa.csl', ignoredPaths: [], done: false });
  });
  it('reads every path by default', () => {
    const plan = planNativeSources({ bibliography: ['/Users/me/a.bib'], csl: '../s.csl' }, {});
    expect(plan).toMatchObject({ bibFiles: ['/Users/me/a.bib'], stylePath: '../s.csl', ignoredPaths: [], done: false });
  });
});
