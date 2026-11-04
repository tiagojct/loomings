import { describe, it, expect } from 'vitest';
import { scanCitations } from './scan.js';

const item = (key, extra = {}) => ({
  key, prefix: '', suffix: '', locator: null, label: null, suppressAuthor: false, ...extra,
});

describe('scanCitations', () => {
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
});
