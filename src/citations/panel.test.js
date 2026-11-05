import { describe, it, expect, beforeEach } from 'vitest';
import { Window } from 'happy-dom';
import {
  shareStyleNote,
  filterLibrary, insertCitation, renderLibrary, bibliographyChoices, toggleBibliography, fileChange, styleChoices,
  languageChoices, referencesMenuHtml, metaChange, nextTab, createReferencesView, withBibliography, choiceIsOn,
} from './panel.js';
import { readCitationMeta, setCitationMeta } from './frontmatter.js';
import { BUNDLED_STYLES } from './style.js';

const entry = (key, authors = '', year = '', title = '', cited = false) => ({ key, authors, year, title, cited });
const library = [
  entry('jacome2020', 'Jácome, Silva', '2020', 'Asthma in schools', true),
  entry('smith1999', 'Smith', '1999', 'Saúde e pulmão'),
];
const report = (over = {}) => ({
  citations: [], bibliography: [], bibliographyMarkdown: '', library, notes: [], markdownSource: '', ...over,
});
const META = {
  bibliography: [], csl: null, lang: null, title: null, references: [], referencesDropped: 0,
};
const file = (name) => ({ name, kind: name.endsWith('.bib') ? 'bib' : 'csl' });

describe('filterLibrary', () => {
  const keys = (query, list = library) => filterLibrary(list, query).map((e) => e.key);

  it('gives the whole library for an empty query', () => {
    expect(keys('')).toEqual(['jacome2020', 'smith1999']);
    expect(keys('   ')).toEqual(['jacome2020', 'smith1999']);
  });

  it('ignores accents and case in both directions', () => {
    expect(keys('jacome')).toEqual(['jacome2020']);
    expect(keys('JÁCOME')).toEqual(['jacome2020']);
    expect(keys('saude')).toEqual(['smith1999']);
    expect(keys('pulmao')).toEqual(['smith1999']);
    expect(keys('jácome', [entry('x', 'Jacome')])).toEqual(['x']);
  });

  it('needs each word, in the key, the authors, the year or the title', () => {
    expect(keys('silva asthma')).toEqual(['jacome2020']);
    expect(keys('smith 1999')).toEqual(['smith1999']);
    expect(keys('silva 1999')).toEqual([]);
  });
});

describe('insertCitation', () => {
  it('inserts a new citation at the position', () => {
    expect(insertCitation('Some text.', 4, 'a')).toEqual({ insert: '[@a]', from: 4 });
  });

  it('adds to a bracket citation that holds the position', () => {
    const text = 'See [@a, p. 3] there.';
    const inside = { insert: '; @b', from: text.indexOf(']') };
    expect(insertCitation(text, text.indexOf('@'), 'b')).toEqual(inside);
    expect(insertCitation(text, text.indexOf('p.'), 'b')).toEqual(inside);
    expect(insertCitation(text, text.indexOf(']'), 'b')).toEqual(inside);
  });

  it('starts a new citation outside the brackets', () => {
    const text = 'See [@a] there.';
    expect(insertCitation(text, text.indexOf('['), 'b')).toEqual({ insert: '[@b]', from: 4 });
    expect(insertCitation(text, text.indexOf(']') + 1, 'b')).toEqual({ insert: '[@b]', from: 8 });
  });

  it('goes after the frontmatter, so a caret at the start cannot break it', () => {
    const text = '---\nbibliography: a.bib\n---\n\nText.\n';
    const body = text.indexOf('\n\nText') + 1;
    expect(insertCitation(text, 0, 'b')).toEqual({ insert: '[@b]', from: body });
    expect(insertCitation(text, 10, 'b')).toEqual({ insert: '[@b]', from: body });
    expect(insertCitation(text, body, 'b')).toEqual({ insert: '[@b]', from: body });
  });

  it('keeps text right after the frontmatter on its own line', () => {
    const text = '---\na: 1\n---\n# Title\n';
    expect(insertCitation(text, 0, 'b')).toEqual({ insert: '[@b]\n\n', from: text.indexOf('#') });
  });

  it('starts a line when the frontmatter ends the document', () => {
    const text = '---\na: 1\n---';
    expect(insertCitation(text, 2, 'b')).toEqual({ insert: '\n[@b]', from: text.length });
  });

  it('does not add to brackets with no citation', () => {
    const text = 'A [link](u) and [note].';
    expect(insertCitation(text, 4, 'b')).toEqual({ insert: '[@b]', from: 4 });
    expect(insertCitation(text, text.indexOf('note'), 'b').insert).toBe('[@b]');
  });
});

describe('renderLibrary', () => {
  /** @type {any} */ let document;
  /** @type {any} */ let root;
  const rows = () => [...root.querySelectorAll('.reference-row')];

  beforeEach(() => {
    const window = new Window();
    document = window.document;
    root = document.createElement('section');
    document.body.appendChild(root);
  });

  it('gives a search field with a label', () => {
    renderLibrary(root, report(), '');
    const input = root.querySelector('input');
    expect(input.getAttribute('type')).toBe('search');
    expect(root.querySelector(`label[for="${input.id}"]`).textContent).toBeTruthy();
  });

  it('gives one button for each entry, and marks a cited entry in text', () => {
    renderLibrary(root, report(), '');
    const buttons = [...root.querySelectorAll('button[data-key]')];
    expect(buttons.map((b) => b.dataset.key)).toEqual(['jacome2020', 'smith1999']);
    expect(buttons[0].textContent).toContain('cited');
    expect(buttons[0].textContent).toContain('Jácome, Silva');
    expect(buttons[0].textContent).toContain('2020');
    expect(buttons[0].textContent).toContain('Asthma in schools');
    expect(buttons[1].textContent).not.toContain('cited');
  });

  it('puts cited keys with no entry first, as rows that cannot insert', () => {
    const citations = [
      { from: 0, to: 1, html: '', markdown: '', missing: ['ghost', 'ghost'] },
      { from: 2, to: 3, html: '', markdown: '', missing: ['jacome2020', 'other'] },
    ];
    renderLibrary(root, report({ citations }), '');
    const texts = rows().map((r) => r.textContent);
    expect(texts).toHaveLength(4);
    expect(texts[0]).toContain('ghost');
    expect(texts[0]).toContain('no entry');
    expect(texts[1]).toContain('other');
    expect(texts[2]).toContain('jacome2020');
    expect(rows()[0].matches('[data-key]')).toBe(false);
    expect(rows()[0].querySelector('button')).toBeNull();
  });

  it('filters the keys with no entry too', () => {
    const citations = [{ from: 0, to: 1, html: '', markdown: '', missing: ['ghost'] }];
    renderLibrary(root, report({ citations }), 'smith');
    expect(rows()).toHaveLength(1);
    expect(rows()[0].textContent).toContain('smith1999');
  });

  it('escapes every label', () => {
    const bad = '<img src=x onerror="alert(1)">';
    const key = `a"><img src=x>`;
    const citations = [{ from: 0, to: 1, html: '', markdown: '', missing: [bad] }];
    renderLibrary(root, report({ citations, library: [entry(key, bad, bad, bad)] }), '');
    expect(root.querySelector('img')).toBeNull();
    expect(root.querySelector('button[data-key]').dataset.key).toBe(key);
    expect(rows()[0].textContent).toContain(bad);
  });

  it('shows at most 200 rows, with a line that says so', () => {
    const big = Array.from({ length: 1240 }, (_, i) => entry(`k${i}`, 'Author', '2000', 'Title'));
    renderLibrary(root, report({ library: big }), '');
    expect(rows()).toHaveLength(200);
    expect(root.querySelector('.references-count').textContent).toBe('Showing 200 of 1,240; type to narrow');
    renderLibrary(root, report({ library: big }), 'k12');
    expect(rows()).toHaveLength(51);
    expect(root.querySelector('.references-count').textContent).toBe('');
  });

  it('says so when no entry matches the filter', () => {
    renderLibrary(root, report(), 'nothing');
    expect(rows()).toHaveLength(0);
    expect(root.querySelector('.references-count').textContent).toContain('No entry');
  });

  it('shows a sentence and Add File for an empty library', () => {
    for (const empty of [null, report({ library: [] })]) {
      renderLibrary(root, empty, '');
      expect(root.querySelector('.references-empty').classList.contains('hidden')).toBe(false);
      expect(root.querySelector('.references-empty p').textContent).toBeTruthy();
      expect(root.querySelector('button[data-action="add-file"]')).not.toBeNull();
      expect(root.querySelector('.references-field').classList.contains('hidden')).toBe(true);
    }
    renderLibrary(root, report(), '');
    expect(root.querySelector('.references-empty').classList.contains('hidden')).toBe(true);
    expect(root.querySelector('.references-field').classList.contains('hidden')).toBe(false);
  });

  it('keeps the sentence honest while the report is on its way', () => {
    renderLibrary(root, null, '', { waiting: true });
    expect(root.querySelector('.references-empty p').textContent).toContain('Reading');
  });

  it('keeps the field and its focus through a new render', () => {
    renderLibrary(root, report(), '');
    const input = root.querySelector('input');
    input.focus();
    input.value = 'smith';
    renderLibrary(root, report(), 'smith');
    expect(root.querySelector('input')).toBe(input);
    expect(input.value).toBe('smith');
    expect(document.activeElement).toBe(input);
  });

  it('keeps the focus on a row when a new report changes the list', () => {
    renderLibrary(root, report(), '');
    root.querySelector('button[data-key="smith1999"]').focus();
    const changed = library.map((e) => ({ ...e, cited: true }));
    renderLibrary(root, report({ library: changed }), '');
    expect(document.activeElement.dataset.key).toBe('smith1999');
    expect(document.activeElement.textContent).toContain('cited');
  });

  it('does not touch the rows when nothing changed', () => {
    renderLibrary(root, report(), '');
    const first = root.querySelector('button[data-key]');
    renderLibrary(root, report(), '');
    expect(root.querySelector('button[data-key]')).toBe(first);
  });
});

describe('the menu choices', () => {
  it('checks a stored bibliography by its base name', () => {
    const meta = { ...META, bibliography: ['folder/Refs.bib', 'gone.bib'] };
    expect(bibliographyChoices(meta, [file('refs.bib'), file('other.bib'), file('x.csl')])).toEqual([
      { name: 'refs.bib', checked: true },
      { name: 'other.bib', checked: false },
    ]);
  });

  it('creates, extends and removes the bibliography list', () => {
    expect(toggleBibliography([], 'a.bib')).toBe('a.bib');
    expect(toggleBibliography(['a.bib'], 'b.bib')).toBe('[a.bib, b.bib]');
    expect(toggleBibliography(['a.bib', 'b.bib'], 'a.bib')).toBe('b.bib');
    expect(toggleBibliography(['x/A.bib'], 'a.bib')).toBeNull();
  });

  it('keeps a name with a comma or a space in the list', () => {
    const value = toggleBibliography(['my refs.bib', 'a, b.bib'], 'c#d.bib');
    const text = setCitationMeta('---\ntitle: T\n---\n', 'bibliography', value);
    expect(readCitationMeta(text).bibliography).toEqual(['my refs.bib', 'a, b.bib', 'c#d.bib']);
  });

  it('puts a chosen file in the place of a missing bibliography', () => {
    expect(fileChange({ ...META, bibliography: ['a.bib'] }, 'a.bib', '/x/a.bib')).toEqual({ key: 'bibliography', value: '/x/a.bib' });
    expect(fileChange({ ...META, bibliography: ['a.bib', 'b.bib'] }, 'b.bib', 'my refs.bib'))
      .toEqual({ key: 'bibliography', value: '[a.bib, my refs.bib]' });
  });

  it('puts a chosen file in the place of a missing style', () => {
    expect(fileChange({ ...META, bibliography: ['a.bib'], csl: 'b.csl' }, 'b.csl', '/x/b.csl')).toEqual({ key: 'csl', value: '/x/b.csl' });
  });

  it('checks one style: the default when the document names none', () => {
    const checked = (meta, files = []) => styleChoices(meta, files).filter((s) => s.checked).map((s) => s.value);
    expect(checked(META)).toEqual(['chicago-author-date']);
    expect(checked({ ...META, csl: 'vancouver' })).toEqual(['vancouver']);
    expect(checked({ ...META, csl: 'nature.csl' }, [file('nature.csl')])).toEqual(['nature.csl']);
    expect(checked({ ...META, csl: 'unknown' })).toEqual([]);
  });

  it('lists the bundled styles and then the stored files', () => {
    const choices = styleChoices(META, [file('nature.csl'), file('refs.bib')]);
    expect(choices.map((s) => s.value)).toEqual([...BUNDLED_STYLES.map((s) => s.id), 'nature.csl']);
    expect(choices[0].label).toBe(BUNDLED_STYLES[0].title);
  });

  it('shows a stored file in place of the bundled style that it hides', () => {
    const choices = styleChoices({ ...META, csl: 'apa' }, [file('APA.csl')]);
    expect(choices.filter((s) => s.checked).map((s) => s.value)).toEqual(['APA.csl']);
    expect(choices.map((s) => s.value)).not.toContain('apa');
  });

  it('checks the locale that the document gets', () => {
    const checked = (lang) => languageChoices({ ...META, lang }).filter((l) => l.checked).map((l) => l.value);
    expect(checked(null)).toEqual(['en-US']);
    expect(checked('pt-PT')).toEqual(['pt-PT']);
    expect(checked('pt')).toEqual(['pt-PT']);
    expect(languageChoices(META).map((l) => l.value)).toEqual(['en-US', 'en-GB', 'pt-PT', 'es-ES']);
  });
});

describe('styleChoices with exact values', () => {
  const checked = (csl) => styleChoices({ ...META, csl }, [], { exact: true }).find((c) => c.checked)?.value ?? null;

  it('checks the default style with no value', () => {
    expect(checked(null)).toBe('chicago-author-date');
  });

  it('checks a bundled style by its id', () => {
    expect(checked('apa')).toBe('apa');
  });

  it('checks nothing for a path or a file name', () => {
    expect(checked('own/apa.csl')).toBe(null);
    expect(checked('apa.csl')).toBe(null);
  });

  it('keeps the base name rule of the web by default', () => {
    expect(styleChoices({ ...META, csl: 'own/apa.csl' }, []).find((c) => c.checked)?.value).toBe('apa');
  });
});

describe('choiceIsOn', () => {
  const choices = [{ value: 'a', label: 'A', checked: true }, { value: 'b', label: 'B', checked: false }];

  it('is true only for the checked value', () => {
    expect(choiceIsOn(choices, 'a')).toBe(true);
    expect(choiceIsOn(choices, 'b')).toBe(false);
    expect(choiceIsOn(choices, 'c')).toBe(false);
  });
});

describe('withBibliography', () => {
  it('gives the name for the first file', () => {
    expect(withBibliography([], 'refs.bib')).toBe('refs.bib');
  });

  it('gives a flow list for a second file', () => {
    expect(withBibliography(['refs.bib'], '../shared/more.bib')).toBe('[refs.bib, ../shared/more.bib]');
  });

  it('keeps two files with one base name: a path names one file', () => {
    expect(withBibliography(['a/refs.bib'], 'b/refs.bib')).toBe('[a/refs.bib, b/refs.bib]');
  });

  it('adds nothing for a file that is in the list', () => {
    expect(withBibliography(['a.bib', 'b.bib'], 'a.bib')).toBe('[a.bib, b.bib]');
  });

  it('writes a value that setCitationMeta keeps as a list', () => {
    const value = withBibliography(['my refs.bib'], "/tmp/o'brien, x.bib");
    const text = setCitationMeta('', 'bibliography', value);
    expect(readCitationMeta(text).bibliography).toEqual(['my refs.bib', "/tmp/o'brien, x.bib"]);
  });
});

describe('referencesMenuHtml', () => {
  const parse = (html) => {
    const root = new Window().document.createElement('div');
    root.innerHTML = html;
    return root;
  };

  it('has the commands, the sections and the note about the browser', () => {
    const root = parse(referencesMenuHtml({ ...META, bibliography: ['a.bib'] }, [file('a.bib'), file('n.csl')]));
    expect(root.querySelector('[data-action="add-file"]').textContent).toContain('Add File…');
    const bib = root.querySelector('[data-bib="a.bib"]');
    expect(bib.getAttribute('role')).toBe('menuitemcheckbox');
    expect(bib.getAttribute('aria-checked')).toBe('true');
    expect(bib.classList.contains('on')).toBe(true);
    const radios = [...root.querySelectorAll('[data-style]')];
    expect(radios).toHaveLength(BUNDLED_STYLES.length + 1);
    expect(radios.every((r) => r.getAttribute('role') === 'menuitemradio')).toBe(true);
    expect(radios.filter((r) => r.getAttribute('aria-checked') === 'true')).toHaveLength(1);
    expect(root.querySelectorAll('[data-lang]')).toHaveLength(4);
    expect(root.querySelector('[data-remove="a.bib"]').textContent).toContain('a.bib');
    expect(root.querySelector('[data-remove="n.csl"]')).not.toBeNull();
    expect(root.textContent).toContain('Files stay in this browser.');
  });

  it('escapes file names', () => {
    const bad = '<img src=x>".bib';
    const root = parse(referencesMenuHtml(META, [{ name: bad, kind: 'bib' }]));
    expect(root.querySelector('img')).toBeNull();
    expect(root.querySelector('[data-bib]').dataset.bib).toBe(bad);
  });

  it('has no remove section without files', () => {
    expect(parse(referencesMenuHtml(META, [])).querySelector('[data-remove]')).toBeNull();
  });
});

describe('metaChange', () => {
  const apply = (text, c) => text.slice(0, c.from) + c.insert + text.slice(c.to);

  it('gives one change that holds only the different text', () => {
    const text = '---\ntitle: T\ncsl: apa\n---\n\nThe body stays.\n';
    const change = metaChange(text, 'csl', 'vancouver');
    expect(change.insert.length).toBeLessThan('vancouver'.length + 1);
    expect(change.to).toBeLessThan(text.indexOf('body'));
    expect(apply(text, change)).toBe(setCitationMeta(text, 'csl', 'vancouver'));
  });

  it('gives null when nothing changes', () => {
    expect(metaChange('---\ncsl: apa\n---\n', 'csl', 'apa')).toBeNull();
  });

  it('makes a frontmatter when there is none', () => {
    const change = metaChange('# Title\n', 'bibliography', 'a.bib');
    expect(apply('# Title\n', change)).toBe('---\nbibliography: a.bib\n---\n# Title\n');
  });

  it('writes the language', () => {
    const text = '---\ntitle: T\n---\n';
    expect(apply(text, metaChange(text, 'lang', 'pt-PT'))).toBe('---\ntitle: T\nlang: pt-PT\n---\n');
  });

  it('lets the 50-line error through to the caller', () => {
    const text = `---\n${'a: 1\n'.repeat(48)}---\n`;
    expect(() => metaChange(text, 'csl', 'apa')).toThrow(/line 50/);
  });
});

describe('nextTab', () => {
  it('follows the arrow keys and wraps', () => {
    expect(nextTab(0, 'ArrowRight', 2)).toBe(1);
    expect(nextTab(1, 'ArrowRight', 2)).toBe(0);
    expect(nextTab(0, 'ArrowLeft', 2)).toBe(1);
    expect(nextTab(1, 'ArrowLeft', 2)).toBe(0);
  });

  it('goes to the ends with Home and End', () => {
    expect(nextTab(1, 'Home', 2)).toBe(0);
    expect(nextTab(0, 'End', 2)).toBe(1);
  });

  it('gives null for other keys', () => {
    expect(nextTab(0, 'ArrowDown', 2)).toBeNull();
    expect(nextTab(0, 'a', 2)).toBeNull();
  });
});

describe('createReferencesView', () => {
  const split = (uses = true) => ({ split: true, uses: () => uses });

  it('shows no tabs outside Split, and does not read the document there', () => {
    const view = createReferencesView();
    view.select('references');
    const uses = () => { throw new Error('read the document'); };
    expect(view.apply({ split: false, uses })).toEqual({ tabs: false, references: false, switched: false });
  });

  it('shows the tabs for a document with citations', () => {
    const view = createReferencesView();
    expect(view.apply(split(false))).toEqual({ tabs: false, references: false, switched: false });
    expect(view.apply(split(true))).toEqual({ tabs: true, references: false, switched: false });
  });

  it('reports a switch when a tab is selected before the apply', () => {
    const view = createReferencesView();
    view.apply(split());
    view.select('references');
    expect(view.apply(split())).toEqual({ tabs: true, references: true, switched: true });
    expect(view.shown).toBe(true);
    expect(view.apply(split())).toEqual({ tabs: true, references: true, switched: false });
    view.select('preview');
    expect(view.apply(split())).toEqual({ tabs: true, references: false, switched: true });
    expect(view.shown).toBe(false);
  });

  it('reports a switch when the menu asks for the library', () => {
    const view = createReferencesView();
    view.apply(split(false));
    view.ask();
    expect(view.apply(split(false))).toEqual({ tabs: true, references: true, switched: true });
  });

  it('keeps the tab for the session, and gives back the preview when the tabs go', () => {
    const view = createReferencesView();
    view.select('references');
    view.apply(split(true));
    expect(view.apply(split(false))).toEqual({ tabs: false, references: false, switched: true });
    expect(view.tab).toBe('references');
    expect(view.apply(split(true))).toEqual({ tabs: true, references: true, switched: true });
  });

  it('forgets the request of the menu with a new document, and keeps the tab', () => {
    const view = createReferencesView();
    view.ask();
    expect(view.apply(split(false)).tabs).toBe(true);
    view.newDocument();
    expect(view.apply(split(false))).toEqual({ tabs: false, references: false, switched: true });
    expect(view.tab).toBe('references');
    expect(view.apply(split(true))).toEqual({ tabs: true, references: true, switched: true });
  });
});

describe('shareStyleNote', () => {
  const shared = (head, body = '[@a]\n') => `---\nreferences: [{"id":"a"}]\n${head}\n---\n${body}`;

  it('names a style that is not bundled', () => {
    expect(shareStyleNote(shared('csl: journal.csl'))).toBe(
      'The link carries the citations; the style journal.csl stays here, so the reader sees the default style.',
    );
    expect(shareStyleNote(shared('csl: /Users/me/journal.csl'))).toContain('the style journal.csl stays here');
  });
  it('names a style file in a folder that has the name of a bundled style', () => {
    const note = 'The link carries the citations; the style file apa.csl stays here, so the reader can see a different style.';
    expect(shareStyleNote(shared('csl: styles/apa.csl'))).toBe(note);
    expect(shareStyleNote(shared('csl: /Users/me/apa.csl'))).toBe(note);
    expect(shareStyleNote(shared('csl: ..\\apa.csl'))).toBe(note);
  });
  it('says nothing for a bundled style or for no style', () => {
    expect(shareStyleNote(shared('csl: apa'))).toBe(null);
    expect(shareStyleNote(shared('csl: vancouver.csl'))).toBe(null);
    expect(shareStyleNote(shared('title: T'))).toBe(null);
  });
  it('says nothing when the link carries no citations', () => {
    expect(shareStyleNote(shared('csl: journal.csl', 'No citations.\n'))).toBe(null);
    expect(shareStyleNote('---\nbibliography: refs.bib\ncsl: journal.csl\n---\n[@a]\n')).toBe(null);
  });
});
