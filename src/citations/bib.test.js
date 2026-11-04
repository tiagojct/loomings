import { describe, expect, it } from 'vitest';
import { parseBibliography } from './bib.js';

const entry = (key, title = 'A title') =>
  `@article{${key},\n  author = {Smith, Anna},\n  title = {${title}},\n  year = {2020},\n}\n`;

describe('parseBibliography', () => {
  it('decodes LaTeX accents', () => {
    const { items, notes } = parseBibliography("@article{j1,\n author = {J{\\'a}come, Tiago},\n title = {T},\n year = {2020}}\n");
    expect(notes).toEqual([]);
    expect(items[0].id).toBe('j1');
    expect(items[0].author[0].family).toBe('Jácome');
  });

  it('resolves @string', () => {
    const { items } = parseBibliography('@string{jn = "Journal of Tests"}\n@article{a1, title={T}, journal = jn, year={2020}}\n');
    expect(items[0]['container-title']).toBe('Journal of Tests');
  });

  it('reads a BOM and CRLF', () => {
    const text = '﻿' + entry('a1').replace(/\n/g, '\r\n');
    const { items, notes } = parseBibliography(text);
    expect(items.map((i) => i.id)).toEqual(['a1']);
    expect(notes).toEqual([]);
  });

  it('accepts empty text', () => {
    expect(parseBibliography('')).toEqual({ items: [], notes: [] });
  });

  it('ignores @comment', () => {
    const { items, notes } = parseBibliography('@comment{ignore {this} text}\n' + entry('a1'));
    expect(items.map((i) => i.id)).toEqual(['a1']);
    expect(notes).toEqual([]);
  });

  it('keeps the good entries when one is not closed', () => {
    const bad = '@article{bad1,\n  title = {Open,\n  year = {2020}\n';
    const text = entry('a1') + bad + entry('a3');
    const { items, notes } = parseBibliography(text);
    expect(items.map((i) => i.id)).toEqual(['a1', 'a3']);
    expect(notes).toHaveLength(1);
    expect(notes[0].line).toBe(5);
    expect(notes[0].key).toBe('bad1');
    expect(notes[0].message).toContain('bad1');
  });

  it('keeps the good entries when one has a syntax error', () => {
    const text = entry('a1') + '@article{bad2,\n title = {x} year = {2020}}\n' + entry('a3');
    const { items, notes } = parseBibliography(text);
    expect(items.map((i) => i.id)).toEqual(['a1', 'a3']);
    expect(notes).toHaveLength(1);
    expect(notes[0].key).toBe('bad2');
    expect(notes[0].line).toBe(5);
  });

  it('keeps the first of a duplicate key', () => {
    const text = entry('a1', 'First') + '\n' + entry('a1', 'Second');
    const { items, notes } = parseBibliography(text);
    expect(items).toHaveLength(1);
    expect(items[0].title).toBe('First');
    expect(notes).toHaveLength(1);
    expect(notes[0].key).toBe('a1');
    expect(notes[0].line).toBe(6);
    expect(notes[0].message).toContain('a1');
  });

  it('does not keep the source text in the items', () => {
    let text = '';
    for (let n = 0; n < 5; n++) text += entry('k' + n, 'Unique title ' + n);
    const { items } = parseBibliography(text);
    const json = JSON.stringify(items[0]);
    expect(json).not.toContain('Unique title 1');
    expect(items[0]._graph).toBeUndefined();
    expect(items[0]['citation-key']).toBeUndefined();
    expect(items[0].id).toBe('k0');
  });

  it('drops a bad @string and keeps the entries', () => {
    const text = '@string{x = }\n' + entry('a1') + entry('a2');
    const { items, notes } = parseBibliography(text);
    expect(items.map((i) => i.id)).toEqual(['a1', 'a2']);
    expect(notes).toHaveLength(1);
    expect(notes[0].line).toBe(0);
  });

  it('does not cut a closed block at a line that starts with @', () => {
    const text = '@article{a1,\n title = {Has\n@word{inside}\n text},\n year = {2020}}\n' + entry('a2');
    const { items, notes } = parseBibliography(text);
    expect(items.map((i) => i.id)).toEqual(['a1', 'a2']);
    expect(notes).toEqual([]);
  });

  it('keeps the first duplicate on the fallback path', () => {
    const text = entry('a1', 'First') + '@article{bad,\n title = {x} year = {1}}\n' + entry('a1', 'Second');
    const { items, notes } = parseBibliography(text);
    expect(items).toHaveLength(1);
    expect(items[0].title).toBe('First');
    expect(notes.map((n) => [n.key, n.line]).sort()).toEqual([['a1', 7], ['bad', 5]]);
  });

  it('counts lines in CRLF text', () => {
    const text = (entry('a1') + '@article{bad,\n title = {x} year = {1}}\n' + entry('a3')).replace(/\n/g, '\r\n');
    const { notes } = parseBibliography(text);
    expect(notes).toHaveLength(1);
    expect(notes[0].line).toBe(5);
  });

  it('reads many unclosed blocks in time, with one summary note', () => {
    const text = `${entry('a1')}${'@article{bad,\n  title = {open\n'.repeat(20000)}`;
    const before = performance.now();
    const { items, notes } = parseBibliography(text);
    expect(performance.now() - before).toBeLessThan(3000);
    expect(items.map((i) => i.id)).toEqual(['a1']);
    expect(notes).toHaveLength(51);
    expect(notes[0].message).toContain('a brace is not closed');
    expect(notes[50]).toEqual({ line: notes[49].line + 2, message: '19950 more notes for this file are not shown.' });
  });

  it('counts the same braces as a counter from each opening', () => {
    const text = '@article{open,\n  title = {a\n@article{in,\n  title = {b},\n  year = {2020}}\n@misc{paren(x), title={c}}\n';
    const { items, notes } = parseBibliography(text);
    expect(items.map((i) => i.id)).toEqual(['in', 'paren(x)']);
    expect(notes.map((n) => n.key)).toEqual(['open']);
  });

  it('closes a block in parentheses with its own parenthesis', () => {
    const { items, notes } = parseBibliography('@article(p1, title = {a) b}, year = {2020})\n@bad{\n');
    expect(notes.length + items.length).toBeGreaterThan(0);
    expect(() => parseBibliography('@article(p1, title = {a}\n@misc(p2, title = {b})\n')).not.toThrow();
  });

  it('finds the line of many duplicates in time', () => {
    const text = entry('a1').repeat(5000);
    const before = performance.now();
    const { items, notes } = parseBibliography(text);
    expect(performance.now() - before).toBeLessThan(5000);
    expect(items).toHaveLength(1);
    expect(notes).toHaveLength(51);
    expect(notes[0].line).toBe(5);
    expect(notes[1].line).toBe(10);
  });

  it('never throws', () => {
    for (const text of ['@', '@article', '@article{', '{{{{', '@@@{}', '@string{x', null, undefined]) {
      expect(() => parseBibliography(/** @type {any} */ (text))).not.toThrow();
    }
  });
});
