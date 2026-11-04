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

  it('never throws', () => {
    for (const text of ['@', '@article', '@article{', '{{{{', '@@@{}', '@string{x', null, undefined]) {
      expect(() => parseBibliography(/** @type {any} */ (text))).not.toThrow();
    }
  });
});
