#!/usr/bin/env node
// Generate the citation fixtures from the web code. The Swift tests run each
// input through JavaScriptCore and expect the same report. A case names its
// style and locale files: the Swift side reads them from macos/Resources.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readCitationMeta, setCitationMeta } from '../../src/citations/frontmatter.js';
import { planNativeSources } from '../../src/citations/library.js';
import { filterLibrary } from '../../src/citations/panel.js';
import { createSession } from '../../src/citations/session.js';
import { checkStyle } from '../../src/citations/style.js';

const here = dirname(fileURLToPath(import.meta.url));
const citations = join(here, '..', '..', 'src', 'citations');
const fixtures = join(here, '..', 'Tests', 'LoomingsCitationsTests', 'Fixtures');
mkdirSync(fixtures, { recursive: true });

const styleFile = (id) => readFileSync(join(citations, 'styles', `${id}.csl`), 'utf8');
const localeFile = (tag) => readFileSync(join(citations, 'locales', `locales-${tag}.xml`), 'utf8');

const BIB = String.raw`@string{jt = "Journal of Tests"}
@article{jacome2020,
  author = {J{\'a}come, Cristina and Almeida, Rute and Fonseca, Jo{\~a}o A.},
  title = {Mobile health tools for {COPD}},
  journal = jt,
  volume = {12},
  number = {3},
  pages = {101--110},
  year = {2020},
  doi = {10.1000/xyz}
}
@book{smith2019,
  author = {Smith, John},
  title = {A book on lung function},
  publisher = {Press},
  address = {Porto},
  year = {2019}
}
@incollection{silva2021,
  author = {Silva, Ana},
  editor = {Costa, Rui},
  title = {Capítulo sobre espirometria},
  booktitle = {Livro de fisiologia},
  publisher = {Porto Editora},
  year = {2021},
  pages = {5--9}
}
@misc{unused2001,
  title = {Never cited},
  year = {2001}
}
`;

const BROKEN_BIB = `@article{good2020,
  author = {Good, Ana},
  title = {A good entry},
  journal = {Journal},
  year = {2020}
}
@article{broken2020,
  author = {Bad, Rui
  title = {An entry that is not closed
@book{after2021,
  author = {After, Eva},
  title = {An entry after the bad one},
  publisher = {Press},
  year = {2021}
}
`;

const DEPENDENT_STYLE = `<?xml version="1.0" encoding="utf-8"?>
<style xmlns="http://purl.org/net/xbiblio/csl" version="1.0" default-locale="en-US">
  <info>
    <title>A dependent journal</title>
    <id>http://www.zotero.org/styles/a-dependent-journal</id>
    <link href="http://www.zotero.org/styles/a-dependent-journal" rel="self"/>
    <link href="http://www.zotero.org/styles/apa" rel="independent-parent"/>
  </info>
</style>
`;

const refs = { name: 'refs.bib', text: BIB };

// Each source field is one that resolveSources gives to the session, but
// `style` and `locale` name a bundled file.
const cases = [
  {
    name: 'apa-en-US',
    source: `---
title: A test
bibliography: refs.bib
reference-section-title: References
---
# Título 🐋

Texto 🌊 [@jacome2020] and [see @smith2019, p. 3, for more; @silva2021].

Then @jacome2020 [p. 5] and [-@smith2019]. Mail a@b.pt and \`[@code]\` stay.

Unknown [@nobody2000] and [@smith2019; @nobody2000].
`,
    sources: { bibs: [refs], style: 'apa', locale: 'en-US' },
  },
  {
    name: 'vancouver-pt-PT',
    source: `---
bibliography: refs.bib
csl: vancouver
lang: pt-PT
reference-section-title: Referências
---
Uma frase [@silva2021]. Outra frase [@jacome2020, p. 7; @smith2019].

Volta ao início [@silva2021].
`,
    sources: { bibs: [refs], style: 'vancouver', locale: 'pt-PT' },
  },
  {
    name: 'broken-entry',
    source: '---\nbibliography: broken.bib\n---\nFirst [@good2020], then [@after2021] and [@broken2020].\n',
    sources: { bibs: [{ name: 'broken.bib', text: BROKEN_BIB }], style: 'apa', locale: 'en-US' },
  },
  {
    name: 'dependent-style',
    source: '---\nbibliography: refs.bib\ncsl: a-dependent-journal.csl\n---\nA [@smith2019].\n',
    sources: { bibs: [refs], styleXml: DEPENDENT_STYLE, locale: 'en-US' },
  },
  {
    name: 'missing-file',
    source: '---\nbibliography: [refs.bib, gone.bib]\n---\nA [@smith2019].\n',
    sources: { bibs: [refs], style: 'apa', locale: 'en-US', missing: ['gone.bib'] },
  },
  {
    name: 'style-not-found',
    source: '---\nbibliography: refs.bib\ncsl: nowhere\n---\nA [@smith2019].\n',
    sources: {
      bibs: [refs],
      style: 'apa',
      locale: 'en-US',
      missing: ['nowhere'],
      styleError: 'The style nowhere was not found. The default style is chicago-author-date.',
    },
  },
  {
    name: 'references-only',
    source: `---
references: [{"id":"inline2022","type":"article-journal","title":"Inline entry","author":[{"family":"Rocha","given":"Eva"}],"issued":{"date-parts":[[2022]]},"container-title":"Revista"}]
---
Inline [@inline2022].
`,
    sources: { bibs: [], style: 'apa', locale: 'en-US' },
  },
  {
    name: 'dropped-references',
    source: '---\nreferences: not a list\n---\nNo entries [@a].\n',
    sources: { bibs: [], style: 'apa', locale: 'en-US' },
  },
  {
    name: 'no-frontmatter',
    source: '# A plain document\n\nIt has [@a] and no frontmatter.\n',
    sources: { bibs: [refs], style: 'apa', locale: 'en-US' },
  },
];

function report({ source, sources }) {
  const { style, locale, styleXml, ...rest } = sources;
  const session = createSession();
  session.setSources({
    ...rest,
    styleXml: styleXml ?? styleFile(style),
    localeXml: localeFile(locale),
    fallbackLocaleXml: localeFile('en-US'),
    lang: locale,
  });
  return session.analyse(source);
}

const metaSources = [
  'No frontmatter.\n',
  '---\nbibliography: [a.bib, "b c.bib"]\ncsl: apa\nlang: pt-PT\nreference-section-title: "Referências"\n---\nBody.\n',
  '---\nbibliography:\n  - a.bib\n  - b.bib\nreferences: [{"id":"one"}, {"title":"no id"}]\n---\nBody.\n',
  '---\nreferences: not a list\n---\nBody.\n',
];

const edits = [
  { source: 'Body.\n', key: 'bibliography', value: 'refs.bib' },
  { source: '---\ncsl: apa\n---\nBody.\n', key: 'csl', value: 'vancouver' },
  { source: '---\ncsl: apa\nlang: pt-PT\n---\nBody.\n', key: 'csl', value: null },
  { source: '---\r\ntitle: Olá\r\n---\r\nBody.\r\n', key: 'bibliography', value: '[a.bib, b.bib]' },
  { source: '---\ncsl: apa\n---\n', key: 'references', value: '[{"id":"one"}]' },
];

const styles = [DEPENDENT_STYLE, styleFile('vancouver'), 'not a style', '<style><info></style>'];

// Each step of the resolve round trip of the native app. The rules are in
// library.js: the Swift test only proves that the bundle gives the same plan.
const OWN_STYLE = styleFile('vancouver');
const plans = [
  { request: { bibliography: ['refs.bib', '/abs/more.bib'], csl: 'apa', lang: 'pt' }, known: {} },
  {
    request: { bibliography: ['refs.bib', '/abs/more.bib'], csl: 'apa', lang: 'pt' },
    known: { files: [{ name: 'refs.bib', kind: 'bib' }], tried: ['refs.bib', '/abs/more.bib', 'apa.csl'] },
  },
  { request: { bibliography: ['refs'], csl: null, lang: null }, known: { tried: ['refs.bib'], noFolder: true } },
  {
    request: { bibliography: [], csl: 'csl/dep.csl', lang: 'en-AU' },
    known: { files: [{ name: 'csl/dep.csl', kind: 'csl', text: DEPENDENT_STYLE }], tried: ['csl/dep.csl'] },
  },
  {
    request: { bibliography: [], csl: 'dep.csl', lang: null },
    known: { files: [{ name: 'dep.csl', kind: 'csl', text: DEPENDENT_STYLE }], tried: ['dep.csl', 'apa.csl'] },
  },
  { request: { bibliography: [], csl: 'nope.csl', lang: null }, known: { tried: ['nope.csl'] } },
  {
    request: { bibliography: ['a/refs.bib', 'b/refs.bib', 'c/refs.bib'], csl: null, lang: null },
    known: { files: [{ name: 'a/refs.bib', kind: 'bib' }, { name: 'b/refs.bib', kind: 'bib' }], tried: ['a/refs.bib', 'b/refs.bib', 'c/refs.bib'] },
  },
  { request: { bibliography: ['latin.bib'], csl: 'own.csl', lang: null }, known: { files: [{ name: 'own.csl', kind: 'csl', text: OWN_STYLE }], tried: ['latin.bib', 'own.csl'], unreadable: ['latin.bib'] } },
];

// The Swift filter must give the same keys as filterLibrary.
const library = [
  { key: 'jacome2020', authors: 'Jácome, Almeida', year: '2020', title: 'Saúde e ciência' },
  { key: 'smith2019', authors: 'Smith', year: '2019', title: 'A book on lung function' },
  { key: 'muller2001', authors: 'Müller', year: '2001', title: 'Über die Lunge' },
  { key: 'nguyen2015', authors: 'Nguyễn', year: '2015', title: '' },
  { key: 'greek2010', authors: 'ΣΩΚΡΑΤΗΣ', year: '2010', title: 'ΑΣΘΜΑ ΚΑΙ ΣΟΦΟΣ' },
  { key: 'russian2011', authors: 'Ёлкин', year: '2011', title: 'Лёгкие' },
  { key: 'japan2012', authors: '山田', year: '2012', title: 'ガイド' },
  { key: 'turkish2013', authors: 'İnan', year: '2013', title: 'Akciğer' },
  { key: 'arabic2014', authors: 'مُحَمَّد', year: '2014', title: 'الرِّئة' },
];
const filterQueries = ['', '   ', 'jacome', 'JÁCOME', 'saude ciencia', 'CIÊNCIA 2020', '2019', 'lung  function', 'muller', 'uber', 'nguyen', 'absent', 'smith absent',
  'σωκρατης', 'ΣΩΚΡΑΤΗΣ', 'σωκρατησ', 'σοφος', 'σοφοσ', 'ασθμα', 'елкин', 'ЛЕГКИЕ', '山田', 'カイト', 'ガイド', 'inan', 'İNAN', 'akciger', 'AKCIĞER', 'محمد', 'الرئة',
  'smith\u00a02019', 'smith\u30002019', 'smith\ufeff2019', 'smith\u200b2019'];

const out = {
  plans: plans.map((p) => ({ ...p, plan: planNativeSources(p.request, p.known) })),
  reports: cases.map((c) => ({ ...c, report: report(c) })),
  meta: metaSources.map((source) => ({ source, meta: readCitationMeta(source) })),
  edits: edits.map((e) => ({ ...e, result: setCitationMeta(e.source, e.key, e.value) })),
  styles: styles.map((xml) => ({ xml, result: checkStyle(xml) })),
  filters: { library, cases: filterQueries.map((query) => ({ query, keys: filterLibrary(library, query).map((e) => e.key) })) },
};

writeFileSync(join(fixtures, 'citation-fixtures.json'), JSON.stringify(out, null, 2) + '\n');
console.log(`wrote ${out.reports.length} citation reports, ${metaSources.length} meta, ${edits.length} edits, ${styles.length} styles`);
