import { describe, it, expect } from 'vitest';
import { escapeHtml } from './html.js';

describe('escapeHtml', () => {
  it('escapes every character that can end a text node or an attribute', () => {
    expect(escapeHtml('<script>alert("x")</script>')).toBe(
      '&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;'
    );
    expect(escapeHtml(`it's`)).toBe('it&#39;s');
    expect(escapeHtml('a & b')).toBe('a &amp; b');
  });

  it('cannot break out of a double-quoted attribute', () => {
    const title = 'He said "hi" onerror="alert(1)';
    const markup = `<span aria-label="Delete ${escapeHtml(title)}">x</span>`;
    expect(markup).toBe(
      '<span aria-label="Delete He said &quot;hi&quot; onerror=&quot;alert(1)">x</span>'
    );
    expect(markup.match(/"/g)).toHaveLength(2);
  });

  it('escapes the ampersand exactly once per pass', () => {
    expect(escapeHtml('&amp;')).toBe('&amp;amp;');
  });

  it('renders null and undefined as an empty string', () => {
    expect(escapeHtml(null)).toBe('');
    expect(escapeHtml(undefined)).toBe('');
  });
});
