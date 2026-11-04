import { describe, it, expect } from 'vitest';
import { EditorState } from '@codemirror/state';
import { SearchQuery } from '@codemirror/search';
import './search.js';
import { withoutAccents, foldText } from './accents.js';

function matches(doc, spec) {
  const state = EditorState.create({ doc });
  const cursor = new SearchQuery(spec).getCursor(state);
  const found = [];
  for (let next = cursor.next(); !next.done; next = cursor.next()) {
    found.push(state.sliceDoc(next.value.from, next.value.to));
  }
  return found;
}

describe('find ignores accents', () => {
  it('finds accented text from a plain query', () => {
    expect(matches('A ciência da informação', { search: 'ciencia' })).toEqual(['ciência']);
    expect(matches('A ciência da informação', { search: 'informacao' })).toEqual(['informação']);
  });

  it('finds plain text from an accented query', () => {
    expect(matches('saude e Saúde', { search: 'saúde' })).toEqual(['saude', 'Saúde']);
  });

  it('finds text whose accents are separate code points', () => {
    expect(matches('ciência', { search: 'ciencia' })).toHaveLength(1);
  });

  it('keeps Markdown markers, which are not accents', () => {
    expect(matches('a ` b ^ c', { search: '`' })).toEqual(['`']);
    expect(matches('a ` b ^ c', { search: '^' })).toEqual(['^']);
    expect(matches('a ` b ^ c', { search: 'a  b' })).toEqual([]);
  });

  it('keeps accents with Match case', () => {
    expect(matches('saude e saúde', { search: 'saúde', caseSensitive: true })).toEqual(['saúde']);
    expect(matches('saude e saúde', { search: 'saude', caseSensitive: true })).toEqual(['saude']);
  });

  it('leaves regular expressions alone', () => {
    expect(matches('saude e saúde', { search: 'sa.de', regexp: true })).toEqual(['saude', 'saúde']);
  });
});

describe('accent helpers', () => {
  it('removes accents and keeps case', () => {
    expect(withoutAccents('Ciência é Saúde')).toBe('Ciencia e Saude');
  });

  it('folds accents and case', () => {
    expect(foldText('JÁCOME')).toBe('jacome');
    expect(foldText('Jacome')).toBe(foldText('Jácome'));
  });
});
