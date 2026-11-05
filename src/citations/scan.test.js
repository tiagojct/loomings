import { describe, it, expect } from 'vitest';
import { scanCitations } from './scan.js';

const item = (key, extra = {}) => ({
  key, prefix: '', suffix: '', locator: null, label: null, suppressAuthor: false, ...extra,
});

describe('scanCitations', () => {
  it('takes a character before a bare key as the regular expression did', () => {
    expect(scanCitations('a@b é@x 9@y _@z 𝒳@astral')).toEqual([]);
    expect(scanCitations('(@a')[0].items[0].key).toBe('a');
    expect(scanCitations('🐋@a')[0].items[0].key).toBe('a');
    expect(scanCitations('a@b @c').map((c) => c.items[0].key)).toEqual(['c']);
  });

  it('takes a character before a key in brackets as the regular expression did', () => {
    expect(scanCitations('[x@a; @b]')[0].items.map((i) => i.key)).toEqual(['b']);
    expect(scanCitations('[é@a]')).toEqual([]);
    expect(scanCitations('[𝒳@a]')).toEqual([]);
    const [c] = scanCitations('[x-@a]');
    expect(c.items[0]).toEqual(item('a', { prefix: 'x-' }));
    expect(scanCitations('[-@a]')[0].items[0].suppressAuthor).toBe(true);
    expect(scanCitations('[x@a @b]')[0].items[0]).toEqual(item('b', { prefix: 'x@a ' }));
  });

  it.each([
    ['a label', 'p. 1'],
    ['no label', '1'],
  ])('reads a locator with %s and a million spaces in time', (_, locator) => {
    const source = `[@k, ${locator}${' '.repeat(1000000)}x, more]`;
    const before = performance.now();
    const [c] = scanCitations(source);
    expect(performance.now() - before).toBeLessThan(1000);
    expect(c.items[0].locator).toBe('1 x');
    expect(c.items[0].suffix).toBe('more');
  });

  it('keeps one space for a run of white space in each affix', () => {
    const [c] = scanCitations('[see  \n  also @k, p.  3 \t 4,  and   more]');
    expect(c.items[0]).toEqual(item('k', { prefix: 'see also ', locator: '3 4', label: 'page', suffix: 'and more' }));
    expect(scanCitations('[@k  and   more]')[0].items[0].suffix).toBe('and more');
  });

  it('reads a paragraph of many lines and many tokens in time', () => {
    const source = `@k\n${'[a]: b\n'.repeat(100000)}`;
    const before = performance.now();
    expect(scanCitations(source)).toHaveLength(1);
    expect(performance.now() - before).toBeLessThan(3000);
  });

  it('trims a locator on each side of a comma', () => {
    expect(scanCitations('[@k, p.   3  ,   more  ]')[0].items[0]).toEqual(item('k', { locator: '3', label: 'page', suffix: 'more' }));
    expect(scanCitations('[@k, 3  ,   more  ]')[0].items[0]).toEqual(item('k', { locator: '3', label: 'page', suffix: 'more' }));
    expect(scanCitations('[@k, p.]')[0].items[0]).toEqual(item('k', { locator: '', label: 'page' }));
    expect(scanCitations('[@k, in press]')[0].items[0]).toEqual(item('k', { suffix: 'in press' }));
  });

  it('checks many keys on one line of many links in time', () => {
    const source = 'https://a.pt/x @k '.repeat(20000);
    const before = performance.now();
    expect(scanCitations(source)).toHaveLength(20000);
    expect(performance.now() - before).toBeLessThan(2000);
  });

  it('returns nothing without an at sign', () => {
    expect(scanCitations('plain [text] here')).toEqual([]);
  });

  it('finds one bracket citation', () => {
    const src = 'See [@key] now.';
    expect(scanCitations(src)).toEqual([{ from: 4, to: 10, bare: false, items: [item('key')] }]);
  });

  it('finds two items', () => {
    const [c] = scanCitations('[@a; @b]');
    expect(c.items.map((i) => i.key)).toEqual(['a', 'b']);
  });

  it('reads prefix, label and locator', () => {
    const [c] = scanCitations('[see @key, p. 3]');
    expect(c.items[0]).toEqual(item('key', { prefix: 'see ', locator: '3', label: 'page' }));
  });

  it('reads a suffix after the locator', () => {
    const [c] = scanCitations('[@key, p. 3, and more]');
    expect(c.items[0]).toEqual(item('key', { locator: '3', label: 'page', suffix: 'and more' }));
  });

  it('maps the other labels', () => {
    const label = (t) => scanCitations(`[@k, ${t} 2]`)[0].items[0].label;
    expect(label('pp.')).toBe('page');
    expect(label('chap.')).toBe('chapter');
    expect(label('sec.')).toBe('section');
    expect(label('vol.')).toBe('volume');
    expect(label('fig.')).toBe('figure');
  });

  it('reads a suffix with no locator', () => {
    const [c] = scanCitations('[@key and more]');
    expect(c.items[0].suffix).toBe('and more');
  });

  it('sets suppressAuthor', () => {
    const [c] = scanCitations('[-@key]');
    expect(c.items[0]).toEqual(item('key', { suppressAuthor: true }));
  });

  it('finds a bare key without the final dot', () => {
    const src = 'As @key. Next';
    expect(scanCitations(src)).toEqual([{ from: 3, to: 7, bare: true, items: [item('key')] }]);
  });

  it('accepts internal punctuation and Unicode letters', () => {
    expect(scanCitations('[@smith:2020]')[0].items[0].key).toBe('smith:2020');
    expect(scanCitations('[@ciência2020]')[0].items[0].key).toBe('ciência2020');
    expect(scanCitations('see @ciência2020')[0].items[0].key).toBe('ciência2020');
    expect(scanCitations('see @a.b-c, and')[0].items[0].key).toBe('a.b-c');
  });

  it('does not match an email address', () => {
    expect(scanCitations('write to a@b.pt now')).toEqual([]);
  });

  it('does not match an escaped at sign', () => {
    expect(scanCitations('\\@key and [\\@key]')).toEqual([]);
  });

  it('skips code spans and fences', () => {
    expect(scanCitations('`[@key]` and `@key`')).toEqual([]);
    expect(scanCitations('```\n[@key]\n@key\n```\n')).toEqual([]);
    expect(scanCitations('    @key\n')).toEqual([]);
  });

  it('skips the frontmatter', () => {
    expect(scanCitations('---\nnote: "@key"\n---\ntext')).toEqual([]);
    expect(scanCitations('---\nnote: x\n---\n@key')).toHaveLength(1);
  });

  it('does not match links', () => {
    expect(scanCitations('[text](url)')).toEqual([]);
    expect(scanCitations('[@key](http://x.org)')).toEqual([]);
    expect(scanCitations('[text](http://a@b)')).toEqual([]);
    expect(scanCitations('[text](http://x.org/@user)')).toEqual([]);
    expect(scanCitations('<http://x.org/@user>')).toEqual([]);
    expect(scanCitations('[text][ref]')).toEqual([]);
    expect(scanCitations('[text]{.cls}')).toEqual([]);
  });

  it('ignores brackets with no key', () => {
    expect(scanCitations('[see this] @')).toEqual([]);
  });

  it('counts an emoji as two units', () => {
    const src = '😀 [@key]';
    const [c] = scanCitations(src);
    expect(c.from).toBe(3);
    expect(src.slice(c.from, c.to)).toBe('[@key]');
  });

  it('gives source offsets with CRLF', () => {
    const src = 'a\r\n\r\nsee `x` [@key]';
    const [c] = scanCitations(src);
    expect(src.slice(c.from, c.to)).toBe('[@key]');
  });

  it('finds a citation after a code span in the same line', () => {
    const src = 'use `a` then @key.';
    const [c] = scanCitations(src);
    expect(src.slice(c.from, c.to)).toBe('@key');
  });

  it('skips link reference definitions', () => {
    expect(scanCitations('[x]: http://a.org/@u "t"\n')).toEqual([]);
    expect(scanCitations('[@k]: http://a.org\n')).toEqual([]);
    expect(scanCitations('   [x]: http://a.org/@u\n\n@k')).toHaveLength(1);
  });

  it('counts backslashes', () => {
    expect(scanCitations('\\\\@k')).toHaveLength(1);
    expect(scanCitations('\\@k')).toEqual([]);
    expect(scanCitations('\\\\[@k]')).toHaveLength(1);
    expect(scanCitations('\\[@k]')).toEqual([]);
    expect(scanCitations('[\\\\@k]')).toHaveLength(1);
    expect(scanCitations('[\\@k]')).toEqual([]);
  });

  it('finds citations in a table cell, heading and blockquote', () => {
    const cases = ['| a | b |\n|---|---|\n| x | [@k] |\n', '## Title [@k]\n', '> quote [@k]\n'];
    for (const src of cases) {
      const r = scanCitations(src);
      expect(r).toHaveLength(1);
      expect(src.slice(r[0].from, r[0].to)).toBe('[@k]');
    }
  });

  it('skips a tilde fence', () => {
    expect(scanCitations('~~~\n[@k] @k\n~~~\n')).toEqual([]);
  });

  it('works with CRLF around fences, headings and quotes', () => {
    const src = '# H [@a]\r\n\r\n```\r\n@x\r\n```\r\n\r\n> q [@b]\r\n';
    const r = scanCitations(src);
    expect(r.map((c) => src.slice(c.from, c.to))).toEqual(['[@a]', '[@b]']);
  });
});

describe('scanCitations: plain URLs', () => {
  const keys = (src) => scanCitations(src).flatMap((c) => c.items.map((it) => it.key));
  it('skips a bare key in a URL', () => {
    expect(keys('See https://x.org/@good for this.')).toEqual([]);
    expect(keys('Hello https://mastodon.social/@tiago')).toEqual([]);
  });
  it('skips a bare key in a URL with no scheme', () => {
    expect(keys('www.x.org/@a')).toEqual([]);
    expect(keys('x.org/@a')).toEqual([]);
  });
  it('skips mailto text', () => {
    expect(keys('Write to mailto:team@x.org now')).toEqual([]);
    expect(keys('mailto:a.b@x.org')).toEqual([]);
  });
  it('skips a key inside brackets that is part of a URL', () => {
    expect(keys('[https://x.org/@a]')).toEqual([]);
    expect(keys('[see https://x.org/@a; @good]')).toEqual(['good']);
  });
  it('keeps citations next to a URL', () => {
    expect(keys('https://x.org/a @good and [@also] www.x.org')).toEqual(['good', 'also']);
    expect(keys('https://x.org/@a\n@good')).toEqual(['good']);
    expect(keys('@good https://x.org/@a')).toEqual(['good']);
  });
  it('gives offsets on the source for a later line', () => {
    const src = 'www.x.org/@a\n\nText @good.';
    const [c] = scanCitations(src);
    expect(src.slice(c.from, c.to)).toBe('@good');
  });
});
