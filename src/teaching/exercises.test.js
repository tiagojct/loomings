import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { readDirectives, parseCheck, parseLimit } from './directives.js';
import { evaluate, scope } from './exercises.js';

const root = fileURLToPath(new URL('../../', import.meta.url));
const read = (path) => readFileSync(join(root, path), 'utf8');

/** @param {string[]} values */
function checks(values) {
  return values.map((value) => parseCheck({ key: 'check', value, line: 0 })).filter((r) => r.ok).map((r) => r.check);
}

describe('frontmatter directives', () => {
  it('reads only check and limit lines inside the frontmatter', () => {
    const source = '---\ncheck: ordered-list 3\nlimit: Introduction 200\ntitle: x\n---\n\ncheck: heading\n';
    const directives = readDirectives(source);
    expect(directives.map((d) => d.key)).toEqual(['check', 'limit']);
    expect(directives.map((d) => d.line)).toEqual([1, 2]);
    expect(directives[0].value).toBe('ordered-list 3');
    expect(readDirectives('check: heading\n')).toEqual([]);
    expect(readDirectives('---\r\nCHECK:  quote  \r\n---\r\n')).toEqual([{ key: 'check', value: 'quote', line: 1 }]);
  });

  it('parses checks with their arguments and defaults', () => {
    const parse = (value) => parseCheck({ key: 'check', value, line: 1 });
    expect(parse('ordered-list 3')).toEqual({ ok: true, check: { type: 'orderedList', items: 3 } });
    expect(parse('bullet-list')).toEqual({ ok: true, check: { type: 'bulletList', items: 2 } });
    expect(parse('heading 2')).toEqual({ ok: true, check: { type: 'heading', level: 2, min: 1 } });
    expect(parse('heading')).toEqual({ ok: true, check: { type: 'heading', level: null, min: 1 } });
    expect(parse('code-block python')).toEqual({ ok: true, check: { type: 'codeBlock', language: 'python' } });
    expect(parse('words 50')).toEqual({ ok: true, check: { type: 'words', min: 50 } });
    expect(parse('Image-Alt')).toEqual({ ok: true, check: { type: 'imageAlt' } });
  });

  it('keeps spaces in a limit heading', () => {
    expect(parseLimit({ key: 'limit', value: 'Methods and data 350', line: 2 }))
      .toEqual({ ok: true, limit: { heading: 'Methods and data', maxWords: 350 } });
  });

  it('turns malformed directives into notes', () => {
    const banana = parseCheck({ key: 'check', value: 'banana', line: 3 });
    expect(banana).toEqual({ ok: false, note: { line: 3, message: 'Unknown check "banana".' } });
    expect(parseLimit({ key: 'limit', value: '200', line: 4 }).ok).toBe(false);
    expect(parseCheck({ key: 'check', value: 'words', line: 5 }).ok).toBe(false);
    const nine = parseCheck({ key: 'check', value: 'heading 9', line: 6 });
    expect(nine).toEqual({ ok: false, note: { line: 6, message: 'A heading level runs from 1 to 6.' } });
    expect(parseCheck({ key: 'check', value: '', line: 7 })).toEqual({
      ok: false, note: { line: 7, message: 'A check needs a kind, for example "check: heading".' },
    });
    expect(parseCheck({ key: 'check', value: 'quote 2', line: 8 })).toEqual({
      ok: false, note: { line: 8, message: '"quote" takes no number.' },
    });
    expect(parseCheck({ key: 'check', value: 'link 0', line: 9 })).toEqual({
      ok: false, note: { line: 9, message: '"link" takes one whole number, for example "link 1".' },
    });
  });
});

describe('exercise checks: shared cases', () => {
  const cases = JSON.parse(read('macos/Tests/LoomingsTeachingTests/Fixtures/check-cases.json'));
  it('has the native cases', () => expect(cases.length).toBeGreaterThanOrEqual(15));
  for (const item of cases) {
    it(item.name, () => {
      const attached = { checks: checks(item.checks), after: null };
      expect(attached.checks.length).toBe(item.checks.length);
      const { results } = evaluate(item.source, attached);
      expect(results.map((r) => r.passed)).toEqual(item.passed);
      for (const r of results) expect(r.label).not.toBe('');
    });
  }
});

describe('exercise checks', () => {
  it('combines frontmatter checks with attached ones; malformed lines become notes', () => {
    const report = evaluate('---\ncheck: quote\ncheck: banana\n---\n\n> said\n', { checks: [{ type: 'strong' }], after: null });
    expect(report.results.map((r) => r.passed)).toEqual([true, false]);
    expect(report.notes.map((n) => n.line)).toEqual([2]);
  });

  it('does not count the frontmatter as words or structure', () => {
    const report = evaluate('---\ncheck: words 3\ntitle: one two three four\n---\n\nHello there.\n');
    expect(report.results.map((r) => r.passed)).toEqual([false]);
    expect(report.results[0].detail).toBe('2 words');
  });

  it('labels and details read as the native app', () => {
    const { results } = evaluate('- a\n- b\n', { checks: checks(['bullet-list 3', 'heading 2 2', 'table', 'words 1']), after: null });
    expect(results.map((r) => [r.label, r.detail])).toEqual([
      ['A bulleted list of 3 items', 'longest has 2 items'],
      ['2 level-2 headings', 'found 0'],
      ['A table with 1 row', 'no table yet'],
      ['At least 1 words', '2 words'],
    ]);
  });

  it('attached checks look only after their anchor', () => {
    const lesson = '# Lesson\n\n1. a\n2. b\n3. c\n\nDone.\n';
    const attached = { checks: [{ type: 'orderedList', items: 3 }], after: lesson };
    expect(evaluate(lesson, attached).results.map((r) => r.passed)).toEqual([false]);
    expect(evaluate(lesson + '\n1. x\n2. y\n3. z\n', attached).results.map((r) => r.passed)).toEqual([true]);
  });

  it('scopes to what follows the lesson, as the native app does', () => {
    const lesson = '# Lesson\n\nDone.\n';
    expect(scope(lesson + 'answer', lesson)).toBe('\nanswer');
    expect(scope('# Lesson\n\nDone.\nmore', '# Old\n\nDone.\n')).toBe('\nmore');
    // An edited last line: what still matches is not the answer.
    expect(scope('# Lesson\n\nDo', lesson)).toBe('');
    // Nothing of the lesson left: all of it is the writer's.
    expect(scope('Totally new text', lesson)).toBe('Totally new text');
    expect(scope('anything', null)).toBe('anything');
    // Never cut through a surrogate pair.
    expect(scope('😀 x', '😀 y')).toBe('x');
    expect(scope('😀x', '😃y')).toBe('😀x');
  });

  it("every bundled lesson's checks parse, fail untouched, and pass with an answer", () => {
    const table = JSON.parse(read('lessons/checks.json'));
    expect(Object.keys(table).length).toBe(6);
    const answers = {
      '01-basics.md': '\n## About me\n\nI teach health informatics in Porto. I like *long* walks by the **river** in the evening. My students write in Markdown.\n',
      '02-lists-quotes.md': '\n- Milk\n- Bread\n- Eggs\n- Rice\n- Tea\n\n1. Boil water.\n2. Add tea.\n3. Wait.\n\n> To be or not to be.\n> Shakespeare\n',
      '03-links-images.md': '\n[My school][fmup] and [the web](https://example.org).\n\n![A red boat on a calm sea](https://example.org/boat.png)\n\n[fmup]: https://sigarra.up.pt/fmup/\n',
      '04-code.md': '\nPress `Ctrl+S` to save `notes.md`.\n\n```python\nprint(1)\n```\n',
      '05-tables-rules.md': '\n| Course | Teacher | Day |\n| --- | --- | ---: |\n| A | B | Mon |\n| C | D | Tue |\n| E | F | Wed |\n',
      '06-frontmatter.md': '\n## One\n\n- a point\n\n> A saying.\n> Someone\n\n## Two\n\n[A link](https://example.org)\n\n| a | b |\n| --- | --- |\n| 1 | 2 |\n',
    };
    for (const [file, values] of Object.entries(table)) {
      const parsed = checks(values);
      expect(parsed.length, file).toBe(values.length);
      const lesson = read(join('lessons', file));
      const attached = { checks: parsed, after: lesson };
      expect(evaluate(lesson, attached).results.every((r) => !r.passed), `${file} untouched`).toBe(true);
      const trimmed = lesson.trim().slice(0, -1);
      expect(evaluate(trimmed, attached).results.every((r) => !r.passed), `${file} last character deleted`).toBe(true);
      const editedFailing = evaluate(trimmed + '\n' + answers[file], attached).results.filter((r) => !r.passed).map((r) => r.label);
      expect(editedFailing, `${file} answer after an edited last line`).toEqual([]);
      const failing = evaluate(lesson + answers[file], attached).results.filter((r) => !r.passed).map((r) => r.label);
      expect(failing, file).toEqual([]);
    }
  });
});
