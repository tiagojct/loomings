import { describe, it, expect, vi } from 'vitest';
import { EditorState } from '@codemirror/state';
import { markdown } from '@codemirror/lang-markdown';
import { autocompletion, completionKeymap, CompletionContext } from '@codemirror/autocomplete';
import { ensureSyntaxTree } from '@codemirror/language';
import { citationCompletions, citationRanges, citationNotes, citationExtensions } from './editor.js';
import { lint } from '../teaching/lint.js';
import { markerName } from '../projector.js';

const completion = vi.hoisted(() => ({ config: /** @type {any} */ (null) }));
vi.mock('@codemirror/autocomplete', async (original) => {
  const real = /** @type {any} */ (await original());
  return { ...real, autocompletion: (config) => { completion.config = config; return real.autocompletion(config); } };
});

const library = [
  { key: 'jacome2020', authors: 'Jácome, Silva', year: '2020', title: 'Asthma in schools', cited: false },
  { key: 'smith1999', authors: 'Smith', year: '1999', title: 'Lung function', cited: true },
];

/** The text has one `|` for the caret. */
function ask(marked, lib = library, explicit = false) {
  const pos = marked.indexOf('|');
  const doc = marked.replace('|', '');
  const state = EditorState.create({ doc, extensions: [markdown()] });
  ensureSyntaxTree(state, doc.length, 5000);
  return citationCompletions(new CompletionContext(state, pos, explicit), lib);
}
const keys = (result) => result?.options.map((o) => o.label);

describe('citationCompletions', () => {
  it('offers a key for a prefix', () => {
    expect(keys(ask('See @jac|'))).toEqual(['jacome2020']);
  });

  it('starts after the at sign, so applying keeps the sign', () => {
    const result = ask('See [@jac|]');
    expect(result.from).toBe(6);
    expect(result.options[0].apply).toBe('jacome2020');
  });

  it('offers every entry for a bare at sign', () => {
    expect(keys(ask('See @|'))).toEqual(['jacome2020', 'smith1999']);
  });

  it('works after a semicolon and a space', () => {
    expect(keys(ask('[@smith1999; @jac|]'))).toEqual(['jacome2020']);
  });

  it('matches the title after a space', () => {
    expect(keys(ask('@jacome asthma|'))).toEqual(['jacome2020']);
    expect(keys(ask('@jacome lung|')) ?? []).toEqual([]);
  });

  it('matches authors and ignores accents and case', () => {
    expect(keys(ask('@Jacome|'))).toEqual(['jacome2020']);
    expect(keys(ask('@JÁCOME|'))).toEqual(['jacome2020']);
    expect(keys(ask('@lung|'))).toEqual(['smith1999']);
  });

  it('shows authors and year as detail and the title as info', () => {
    const [option] = ask('@jac|').options;
    expect(option.detail).toBe('Jácome, Silva 2020');
    expect(option.info).toBe('Asthma in schools');
  });

  it('offers nothing in an email address', () => {
    expect(ask('write to a@jac|')).toBeNull();
  });

  it('offers nothing in a code span or a code block', () => {
    expect(ask('Use `@jac|` here')).toBeNull();
    expect(ask('```\n@jac|\n```')).toBeNull();
    expect(ask('    @jac|')).toBeNull();
  });

  it('offers nothing in the frontmatter', () => {
    expect(ask('---\ntitle: a @jac|\n---\n\nText\n')).toBeNull();
  });

  it('offers nothing with an empty library', () => {
    expect(ask('See @|', [])).toBeNull();
  });

  it('offers nothing when no entry matches', () => {
    expect(ask('@zzz|')).toBeNull();
  });

  it('accepts a function for the library', () => {
    expect(keys(ask('@jac|', /** @type {any} */ (() => library)))).toEqual(['jacome2020']);
  });
});

describe('citationRanges', () => {
  it('gives the ranges of the citations and marks the unknown keys', () => {
    const report = { citations: [{ from: 4, to: 10, missing: [] }, { from: 20, to: 30, missing: ['x'] }] };
    expect(citationRanges(report, 25)).toEqual([{ from: 4, to: 10, missing: false }, { from: 20, to: 25, missing: true }]);
  });

  it('gives nothing without a report', () => {
    expect(citationRanges(null, 10)).toEqual([]);
  });

  it('drops a range that is empty after the clamp', () => {
    expect(citationRanges({ citations: [{ from: 12, to: 14, missing: [] }] }, 10)).toEqual([]);
  });
});

describe('citationNotes', () => {
  it('keeps a note with a range and clamps a stale range', () => {
    const notes = citationNotes({ notes: [{ from: 40, to: 60, message: 'The style cannot format this citation.' }] }, 50);
    expect(notes).toEqual([{ from: 40, to: 50, message: 'The style cannot format this citation.', rule: 'citation' }]);
    expect(citationNotes({ notes: [{ from: 70, to: 80, message: 'm' }] }, 50)[0]).toMatchObject({ from: 50, to: 50 });
  });

  it('makes a file-level note with no line to go to', () => {
    const [note] = citationNotes({ notes: [{ from: 0, to: 0, file: 'refs.bib', line: 3, message: 'Bad entry.' }] }, 50);
    expect(note.fileLevel).toBe(true);
    expect(note.message).toBe('refs.bib, line 4: Bad entry.');
  });

  it('gives a missing file the action to add it', () => {
    const [note] = citationNotes({ notes: [{ from: 0, to: 0, file: 'references.bib', line: 0, message: 'The file references.bib is missing.' }] }, 0);
    expect(note.message).toBe('No file called references.bib in this browser.');
    expect(note.action).toEqual({ title: 'Add references.bib', kind: 'add-file' });
    expect(note.fileLevel).toBe(true);
  });

  it('gives one note for a note without a file', () => {
    const notes = citationNotes({ notes: [{ from: 0, to: 0, line: 0, message: 'One entry in references has no text id. It is not used.' }] }, 5);
    expect(notes).toHaveLength(1);
    expect(notes[0].fileLevel).toBe(true);
  });

  it('gives nothing without a report', () => {
    expect(citationNotes(null, 10)).toEqual([]);
  });
});

describe('the rest of the editor', () => {
  it("the learner's checker gives no note on a citation", () => {
    const source = '---\nbibliography: refs.bib\n---\n\nSee [@key] and [@a; @b, p. 3], also @key and [-@k].\n';
    expect(lint(source)).toEqual([]);
  });

  it('the projector caption ignores an at sign', () => {
    expect(markerName('@')).toBeNull();
    expect(markerName('[@')).toBeNull();
    expect(markerName('- @')).toBeNull();
  });

  it('the completion Enter key passes when no panel is open', () => {
    const state = EditorState.create({ doc: 'a', extensions: [autocompletion()] });
    const enter = completionKeymap.find((k) => k.key === 'Enter');
    expect(enter.run({ state })).toBe(false);
  });

  it('builds the extensions', () => {
    expect(citationExtensions(() => null, () => []).length).toBeGreaterThan(0);
  });

  it('completes from the held library, with no scan of the document', () => {
    const getReport = vi.fn(() => null);
    const getLibrary = vi.fn(() => library);
    citationExtensions(getReport, getLibrary);
    const doc = 'See @jac';
    const state = EditorState.create({ doc, extensions: [markdown()] });
    ensureSyntaxTree(state, doc.length, 5000);
    const result = completion.config.override[0](new CompletionContext(state, doc.length, false));
    expect(result.options.map((o) => o.label)).toEqual(['jacome2020']);
    expect(getLibrary).toHaveBeenCalledTimes(1);
    expect(getReport).not.toHaveBeenCalled();
  });
});
