import { describe, it, expect } from 'vitest';
import { readCitationMeta, setCitationMeta } from './frontmatter.js';

const empty = { bibliography: [], csl: null, lang: null, title: null, references: [] };

describe('readCitationMeta', () => {
  it('returns defaults without frontmatter', () => {
    expect(readCitationMeta('# Title\n\ntext')).toEqual(empty);
    expect(readCitationMeta('')).toEqual(empty);
  });

  it('reads one name', () => {
    expect(readCitationMeta('---\nbibliography: refs.bib\n---\n').bibliography).toEqual(['refs.bib']);
  });

  it('reads a flow list', () => {
    expect(readCitationMeta('---\nbibliography: [a.bib, b.bib]\n---\n').bibliography).toEqual(['a.bib', 'b.bib']);
  });

  it('reads a block list', () => {
    const src = '---\nbibliography:\n  - a.bib\n  - "b c.bib"\ncsl: x.csl\n---\n';
    const meta = readCitationMeta(src);
    expect(meta.bibliography).toEqual(['a.bib', 'b c.bib']);
    expect(meta.csl).toBe('x.csl');
  });

  it('reads quotes and removes comments outside quotes', () => {
    const src = "---\ncsl: 'apa #1.csl' # note\nlang: \"pt-PT\"\nbibliography: a.bib # c\n---\n";
    const meta = readCitationMeta(src);
    expect(meta.csl).toBe('apa #1.csl');
    expect(meta.lang).toBe('pt-PT');
    expect(meta.bibliography).toEqual(['a.bib']);
  });

  it('reads the section title', () => {
    expect(readCitationMeta('---\nreference-section-title: Referências\n---\n').title).toBe('Referências');
  });

  it('gives null for empty csl and lang', () => {
    expect(readCitationMeta('---\ncsl:\nlang: ""\n---\n')).toEqual(empty);
  });

  it('ignores frontmatter that closes after line 50', () => {
    const src = '---\n' + 'x: 1\n'.repeat(49) + 'bibliography: a.bib\n---\n';
    expect(readCitationMeta(src)).toEqual(empty);
  });

  it('ignores keys after the frontmatter', () => {
    expect(readCitationMeta('---\ncsl: a.csl\n---\n\nbibliography: b.bib\n').bibliography).toEqual([]);
  });

  it('reads one-line JSON references as objects', () => {
    const src = '---\nreferences: [{"id":"a","title":"A # b"},{"id":"b"}]\n---\n';
    expect(readCitationMeta(src).references).toEqual([{ id: 'a', title: 'A # b' }, { id: 'b' }]);
  });

  it('keeps only objects with a string id', () => {
    const src = '---\nreferences: [{"id":"a"},{"id":3},1,null,"x",{"title":"t"}]\n---\n';
    expect(readCitationMeta(src).references).toEqual([{ id: 'a' }]);
  });

  it('gives an empty array for malformed references', () => {
    expect(readCitationMeta('---\nreferences: [{"id":\n---\n').references).toEqual([]);
    expect(readCitationMeta('---\nreferences: {"id":"a"}\n---\n').references).toEqual([]);
    expect(readCitationMeta('---\nreferences:\n---\n').references).toEqual([]);
  });

  it('removes a comment after references', () => {
    const src = '---\nreferences: [{"id":"a","t":"x # y"}] # note\n---\n';
    expect(readCitationMeta(src).references).toEqual([{ id: 'a', t: 'x # y' }]);
  });

  it('keeps an apostrophe inside a flow list name', () => {
    expect(readCitationMeta("---\nbibliography: [o'brien.bib, b.bib]\n---\n").bibliography).toEqual([
      "o'brien.bib",
      'b.bib',
    ]);
  });

  it('reads a flow list over several lines', () => {
    const src = '---\nbibliography: [a.bib, # first\n  b.bib,\n  "c d.bib"]\ncsl: x.csl\n---\n';
    const meta = readCitationMeta(src);
    expect(meta.bibliography).toEqual(['a.bib', 'b.bib', 'c d.bib']);
    expect(meta.csl).toBe('x.csl');
  });

  it('reads the first of duplicate keys', () => {
    expect(readCitationMeta('---\ncsl: a.csl\ncsl: b.csl\n---\n').csl).toBe('a.csl');
  });

  it('accepts a closing line at line 50', () => {
    const src = '---\n' + 'x: 1\n'.repeat(47) + 'bibliography: a.bib\n---\n';
    expect(src.split('\n')[49]).toBe('---');
    expect(readCitationMeta(src).bibliography).toEqual(['a.bib']);
  });

  it('reads CRLF sources', () => {
    expect(readCitationMeta('---\r\nbibliography: a.bib\r\n---\r\n').bibliography).toEqual(['a.bib']);
  });
});

describe('setCitationMeta', () => {
  it('replaces a key', () => {
    expect(setCitationMeta('---\ncsl: a.csl\n---\nbody', 'csl', 'b.csl')).toBe('---\ncsl: b.csl\n---\nbody');
  });

  it('replaces a block list with one line', () => {
    const src = '---\nbibliography:\n  - a.bib\n  - b.bib\ncsl: x.csl\n---\n';
    expect(setCitationMeta(src, 'bibliography', 'c.bib')).toBe('---\nbibliography: c.bib\ncsl: x.csl\n---\n');
  });

  it('adds a key before the closing line', () => {
    expect(setCitationMeta('---\ntitle: T\n---\nbody', 'csl', 'a.csl')).toBe('---\ntitle: T\ncsl: a.csl\n---\nbody');
  });

  it('removes a key at null, with its block list', () => {
    const src = '---\ntitle: T\nbibliography:\n  - a.bib\ncsl: x.csl\n---\n';
    expect(setCitationMeta(src, 'bibliography', null)).toBe('---\ntitle: T\ncsl: x.csl\n---\n');
  });

  it('returns the source when it removes a missing key', () => {
    expect(setCitationMeta('# Hi\n', 'csl', null)).toBe('# Hi\n');
    expect(setCitationMeta('---\na: 1\n---\n', 'csl', null)).toBe('---\na: 1\n---\n');
  });

  it('creates a frontmatter when none exists', () => {
    expect(setCitationMeta('# Hi\n', 'bibliography', 'a.bib')).toBe('---\nbibliography: a.bib\n---\n# Hi\n');
  });

  it('keeps CRLF', () => {
    expect(setCitationMeta('---\r\ntitle: T\r\n---\r\nbody', 'csl', 'a.csl')).toBe(
      '---\r\ntitle: T\r\ncsl: a.csl\r\n---\r\nbody',
    );
    expect(setCitationMeta('# Hi\r\nx', 'csl', 'a.csl')).toBe('---\r\ncsl: a.csl\r\n---\r\n# Hi\r\nx');
  });

  it('keeps check lines', () => {
    const src = '---\ncheck: heading 2\ncsl: a.csl\nlimit: Intro 100\n---\n';
    expect(setCitationMeta(src, 'csl', 'b.csl')).toBe('---\ncheck: heading 2\ncsl: b.csl\nlimit: Intro 100\n---\n');
  });

  it('quotes a value that needs it, and the result reads back', () => {
    const out = setCitationMeta('', 'csl', 'a #1: b.csl');
    expect(readCitationMeta(out).csl).toBe('a #1: b.csl');
  });

  it('writes references as given and reads them back', () => {
    const json = '[{"id":"a","title":"A # b"}]';
    const out = setCitationMeta('---\ntitle: T\n---\n', 'references', json);
    expect(out).toBe('---\ntitle: T\nreferences: ' + json + '\n---\n');
    expect(readCitationMeta(out).references).toEqual([{ id: 'a', title: 'A # b' }]);
    expect(setCitationMeta(out, 'references', null)).toBe('---\ntitle: T\n---\n');
  });

  it('replaces the first duplicate and removes the others', () => {
    expect(setCitationMeta('---\ncsl: a.csl\nx: 1\ncsl: b.csl\n---\n', 'csl', 'c.csl')).toBe(
      '---\ncsl: c.csl\nx: 1\n---\n',
    );
    expect(setCitationMeta('---\ncsl: a.csl\nx: 1\ncsl: b.csl\n---\n', 'csl', null)).toBe('---\nx: 1\n---\n');
  });

  it('works when the closing line is line 50', () => {
    const src = '---\n' + 'x: 1\n'.repeat(47) + '---\n';
    expect(readCitationMeta(setCitationMeta(src, 'csl', 'a.csl')).csl).toBe('a.csl');
  });

  it('rejects a value with a line break, for every key', () => {
    for (const key of ['bibliography', 'csl', 'references']) {
      expect(() => setCitationMeta('', key, 'a\nb')).toThrow(/line break/);
      expect(() => setCitationMeta('', key, 'a\rb')).toThrow(/line break/);
    }
  });

  it('rejects references that are not a JSON array', () => {
    expect(() => setCitationMeta('', 'references', '{"id":"a"}')).toThrow(/JSON array/);
    expect(() => setCitationMeta('', 'references', '[{"id":')).toThrow(/JSON array/);
  });

  it('writes a well-formed flow list raw and quotes other bracket values', () => {
    expect(setCitationMeta('', 'bibliography', '[a.bib, b.bib]')).toBe('---\nbibliography: [a.bib, b.bib]\n---\n');
    const out = setCitationMeta('', 'bibliography', '[x].bib');
    expect(readCitationMeta(out).bibliography).toEqual(['[x].bib']);
    const out2 = setCitationMeta('', 'bibliography', '[a.bib, [b].bib]');
    expect(readCitationMeta(out2).bibliography).toEqual(['[a.bib, [b].bib]']);
  });
});
