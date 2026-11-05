import { describe, it, expect } from 'vitest';
import { cleanCitationHtml, toMarkdown, applyCitations, withReferences } from './output.js';
import { renderMarkdown } from '../markdown.js';

const lines = (s) => s.split(/\r\n|\r|\n/).length;

describe('cleanCitationHtml', () => {
  it('keeps the inline tags and removes their attributes', () => {
    expect(cleanCitationHtml('<i>a</i><b>b</b><sup>1</sup><sub>2</sub>')).toBe('<i>a</i><b>b</b><sup>1</sup><sub>2</sub>');
    expect(cleanCitationHtml('<span style="color:red" onclick="x()">a</span>')).toBe('<span>a</span>');
    expect(cleanCitationHtml('<i class="x">a</i>')).toBe('<i>a</i>');
  });
  it('maps em to i', () => {
    expect(cleanCitationHtml('<em>a</em>')).toBe('<i>a</i>');
    expect(cleanCitationHtml('<EM class="x">a</EM>')).toBe('<i>a</i>');
    expect(toMarkdown('<em>a</em>')).toBe('*a*');
  });
  it('keeps an anchor with a safe href only', () => {
    expect(cleanCitationHtml('<a href="https://x.org/a" onclick="y()">t</a>')).toBe('<a href="https://x.org/a">t</a>');
  });
  it('gives text with no anchor for an unsafe or absent href', () => {
    expect(cleanCitationHtml('<a href="javascript:alert(1)">t</a>')).toBe('t');
    expect(cleanCitationHtml("<a href='data:text/html,x'>t</a>")).toBe('t');
    expect(cleanCitationHtml('<a>t</a>')).toBe('t');
    expect(cleanCitationHtml('<a href="java&#115;cript:alert(1)">t</a>')).toBe('t');
  });
  it('removes the doi.org link that citeproc puts on a value that is not a URL', () => {
    expect(cleanCitationHtml('<a href="https://doi.org/javascript:alert(1)">javascript:alert(1)</a>')).toBe('javascript:alert(1)');
    expect(cleanCitationHtml('<a href="https://doi.org/www.x.org">www.x.org</a>')).toBe('www.x.org');
  });
  it('keeps a real DOI link', () => {
    const doi = '<a href="https://doi.org/10.1/abc">10.1/abc</a>';
    expect(cleanCitationHtml(doi)).toBe(doi);
    const url = '<a href="https://doi.org/abc">https://doi.org/abc</a>';
    expect(cleanCitationHtml(url)).toBe(url);
  });
  it('cannot be broken out of with a quote in the href', () => {
    expect(cleanCitationHtml(`<a href='https://x.org/"onclick="y'>t</a>`)).toBe('<a href="https://x.org/&quot;onclick=&quot;y">t</a>');
    expect(cleanCitationHtml('<a href="https://x.org/" onmouseover="y">t</a>')).toBe('<a href="https://x.org/">t</a>');
  });
  it('keeps a div with an allowed class only', () => {
    for (const c of ['csl-entry', 'csl-left-margin', 'csl-right-inline', 'csl-indent', 'csl-block']) {
      expect(cleanCitationHtml(`<div class="${c}">a</div>`)).toBe(`<div class="${c}">a</div>`);
    }
    expect(cleanCitationHtml('<div class="evil">a</div>')).toBe('&lt;div class="evil"&gt;a&lt;/div&gt;');
    expect(cleanCitationHtml('<div>a</div>')).toBe('&lt;div&gt;a&lt;/div&gt;');
  });
  it('escapes every other tag as text', () => {
    expect(cleanCitationHtml('<script>alert(1)</script>')).toBe('&lt;script&gt;alert(1)&lt;/script&gt;');
    expect(cleanCitationHtml('<img src=x onerror=y>')).toBe('&lt;img src=x onerror=y&gt;');
    expect(cleanCitationHtml('a < b > c')).toBe('a &lt; b &gt; c');
    expect(cleanCitationHtml('<i onclick="x>a')).toBe('&lt;i onclick="x&gt;a');
  });
  it('keeps entities', () => {
    expect(cleanCitationHtml('a &#38; b &#60;script&#62; &#x26;')).toBe('a &#38; b &#60;script&#62; &#x26;');
    expect(cleanCitationHtml('a & b')).toBe('a &amp; b');
  });
  it('gives balanced output', () => {
    expect(cleanCitationHtml('<i>a')).toBe('<i>a</i>');
    expect(cleanCitationHtml('a</i>')).toBe('a&lt;/i&gt;');
    expect(cleanCitationHtml('</div></span>')).toBe('&lt;/div&gt;&lt;/span&gt;');
    expect(cleanCitationHtml('<b><i>a</b>')).toBe('<b><i>a</i></b>');
    expect(cleanCitationHtml('<i>a<br>b</i>')).toBe('<i>a&lt;br&gt;b</i>');
  });
});

describe('toMarkdown', () => {
  it('writes emphasis and strong', () => {
    expect(toMarkdown('<i>a</i> and <b>b</b>')).toBe('*a* and **b**');
    expect(toMarkdown('x<i> a </i>b')).toBe('x *a* b');
    expect(toMarkdown('<i></i>')).toBe('');
    expect(toMarkdown('<i>a <i>b</i> c</i>')).toBe('*a b c*');
  });
  it('writes a superscript form only when each character has one', () => {
    expect(toMarkdown('<sup>1(p3)</sup>')).toBe('1(p3)');
    expect(toMarkdown('<sup>1-3</sup>')).toBe('¹⁻³');
    expect(toMarkdown('<sup>1–3</sup>')).toBe('¹⁻³');
    expect(toMarkdown('<sup>(1)</sup>')).toBe('⁽¹⁾');
    expect(toMarkdown('<sup>1, 2</sup>')).toBe('¹, ²');
    expect(toMarkdown('<sup>st</sup>')).toBe('st');
    expect(toMarkdown('a<sup>1.2</sup>')).toBe('a1.2');
    expect(toMarkdown('<sup><i>n</i>2</sup>')).toBe('*n*2');
  });

  it('keeps the text of a sub', () => {
    expect(toMarkdown('H<sub>2</sub>O')).toBe('H2O');
  });

  it('writes superscript digits and drops sub and span tags', () => {
    expect(toMarkdown('<sup>1,23</sup>')).toBe('¹,²³');
    expect(toMarkdown('H<sub>2</sub>O <span>x</span>')).toBe('H2O x');
  });
  it('writes links', () => {
    expect(toMarkdown('<a href="https://doi.org/10.1/abc">10.1/abc</a>')).toBe('[10.1/abc](https://doi.org/10.1/abc)');
    expect(toMarkdown('<a href="https://x.org/a">https://x.org/a</a>')).toBe('https://x.org/a');
    expect(toMarkdown('<a href="https://x.org/a(b)">t</a>')).toBe('[t](https://x.org/a\\(b\\))');
    expect(toMarkdown('<a href="https://x.org/?a=1&#38;b=2">https://x.org/?a=1&#38;b=2</a>')).toBe('https://x.org/?a=1&b=2');
  });
  it('gives no link for an unsafe href', () => {
    expect(toMarkdown('<a href="javascript:x">t</a>')).toBe('t');
  });
  it('decodes entities once', () => {
    expect(toMarkdown('a &#38; b &#x26; c &#60;d&#62;')).toBe('a & b & c \\<d>');
    expect(toMarkdown('&#38;#60;')).toBe('\\&#60;');
    expect(toMarkdown('&#1114112;')).toBe('\\&#1114112;');
  });
  it('escapes Markdown specials', () => {
    expect(toMarkdown('a\\b `c` *d* _e_ [f]')).toBe('a\\\\b \\`c\\` \\*d\\* \\_e\\_ \\[f\\]');
  });
  it('keeps a leading number from being a list item', () => {
    expect(toMarkdown('1. Smith')).toBe('1\\. Smith');
    expect(toMarkdown('12) Smith')).toBe('12\\) Smith');
    expect(toMarkdown('- Smith')).toBe('\\- Smith');
  });
  it('gives one line', () => {
    expect(toMarkdown('  <div class="csl-entry">\n    <div class="csl-left-margin">1.</div><div class="csl-right-inline">Smith J.</div>\n  </div>\n')).toBe('1\\. Smith J.');
    expect(toMarkdown('a\nb\r\nc d')).toBe('a b c d');
  });
  it('keeps a no-break space', () => {
    expect(toMarkdown('p. 3')).toBe('p. 3');
  });
  it('escapes a tag that is not allowed', () => {
    expect(toMarkdown('<script>x</script>')).toBe('\\<script>x\\</script>');
  });
});

const report = (citations) => ({ citations });

describe('applyCitations', () => {
  const source = 'See [@a] and\n[@b;\n@c] end.\n';
  const from = source.indexOf('[@a]');
  const start = source.indexOf('[@b');
  const r = report([
    { from, to: from + 4, html: '(A)', markdown: '(A)', missing: [] },
    { from: start, to: source.indexOf(' end'), html: '[@b;\n@c]', markdown: '[@b;\n@c]', missing: ['b', 'c'] },
  ]);
  it('keeps the line count and removes the citation text', () => {
    const { text } = applyCitations(source, r);
    expect(lines(text)).toBe(lines(source));
    expect(text).not.toContain('@');
    expect(text).toContain(' end.');
  });
  it('fills the rendered HTML', () => {
    const { text, fill } = applyCitations(source, r);
    const html = fill(renderMarkdown(text));
    expect(html).toContain('<span class="cite">(A)</span>');
    expect(html).toContain('<span class="cite cite-missing">[@b;\n@c]</span>');
    expect(html).not.toMatch(/[-]/);
  });
  it('does not put a tag in an attribute', () => {
    const src = '![[@a]](x.png)\n';
    const at = src.indexOf('[@a]');
    const { text, fill } = applyCitations(src, report([
      { from: at, to: at + 4, html: '<i>A "q"</i>', markdown: '', missing: [] },
    ]));
    const html = fill(renderMarkdown(text));
    expect(html).toContain('alt="A &quot;q&quot;"');
    expect(html).not.toContain('<span');
  });
  it('uses markers that the source does not contain', () => {
    const src = 'x0 [@a]';
    const at = src.indexOf('[@a]');
    const { text, fill } = applyCitations(src, report([{ from: at, to: at + 4, html: 'A', markdown: '', missing: [] }]));
    const html = fill(renderMarkdown(text));
    expect(html).toContain('x0 <span class="cite">A</span>');
  });
  it('passes text through with no citations', () => {
    const { text, fill } = applyCitations('a\n', report([]));
    expect(text).toBe('a\n');
    expect(fill('<p>a</p>')).toBe('<p>a</p>');
  });
});

describe('withReferences', () => {
  const c = (s, sub, markdown) => ({ from: s.indexOf(sub), to: s.indexOf(sub) + sub.length, html: '', markdown, missing: [] });
  it('replaces each range and keeps the lines', () => {
    const s = 'A [@a;\n@b] c\nlast';
    const out = withReferences(s, [c(s, '[@a;\n@b]', '(A)')], null, '');
    expect(out).toBe('A (A)\n c\nlast');
  });
  it('does not add line breaks to a literal citation', () => {
    const s = 'A [@a;\n@b] c';
    expect(withReferences(s, [c(s, '[@a;\n@b]', '[@a;\n@b]')], null, '')).toBe(s);
  });
  it('adds a blank line, the title and the entries', () => {
    expect(withReferences('a', [], 'Refs', '1\\. x')).toBe('a\n\n## Refs\n\n1\\. x');
    expect(withReferences('a\n', [], 'Refs', 'x')).toBe('a\n\n## Refs\n\nx');
    expect(withReferences('a\n', [], null, 'x')).toBe('a\n\nx');
  });
  it('adds nothing without references', () => {
    expect(withReferences('a\n', [], 'Refs', '')).toBe('a\n');
  });
});

describe('text with many tags', () => {
  it('reads closing tags with no opening tag in time', () => {
    const html = '<i></b>'.repeat(150000);
    const before = performance.now();
    expect(cleanCitationHtml(html).startsWith('<i>&lt;/b&gt;<i>')).toBe(true);
    expect(performance.now() - before).toBeLessThan(2000);
  });

  it('closes the tags inside a closing tag', () => {
    expect(cleanCitationHtml('<i><b><sup>x</i>y</b>')).toBe('<i><b><sup>x</sup></b></i>y&lt;/b&gt;');
  });

  it('reads deep tags in time, and marks only the outer one', () => {
    const before = performance.now();
    expect(toMarkdown(`${'<i>'.repeat(300000)}x`)).toBe('*x*');
    expect(performance.now() - before).toBeLessThan(2000);
  });
});

describe('withReferences with a fence', () => {
  const close = (text) => withReferences(text, [], 'References', 'Entry.');

  it('adds the list after a closed fence with no extra line', () => {
    expect(close('a\n\n```\ncode\n```\n')).toBe('a\n\n```\ncode\n```\n\n## References\n\nEntry.');
  });

  it('closes a final fence that is open', () => {
    expect(close('a\n\n```\ncode\n')).toBe('a\n\n```\ncode\n```\n\n## References\n\nEntry.');
    expect(close('a\n\n```\ncode')).toBe('a\n\n```\ncode\n```\n\n## References\n\nEntry.');
    expect(close('~~~~ js\ncode\n```\n')).toBe('~~~~ js\ncode\n```\n~~~~\n\n## References\n\nEntry.');
    expect(close('```')).toBe('```\n```\n\n## References\n\nEntry.');
  });

  it('keeps each line of the source at its number', () => {
    const text = '---\nreferences: []\n---\nA\n\n```\none\ntwo\n';
    const lines = text.split('\n').slice(0, -1);
    expect(close(text).split('\n').slice(0, lines.length)).toEqual(lines);
  });

  it('sees a closing line with a longer marker or an indent as a close', () => {
    expect(close('```\ncode\n`````\n')).toBe('```\ncode\n`````\n\n## References\n\nEntry.');
    expect(close('```\ncode\n   ```  \n')).toBe('```\ncode\n   ```  \n\n## References\n\nEntry.');
  });

  it('does not take a line that cannot close the fence as a close', () => {
    expect(close('````\ncode\n```\n')).toBe('````\ncode\n```\n````\n\n## References\n\nEntry.');
    expect(close('```\ncode\n    ```\n')).toBe('```\ncode\n    ```\n```\n\n## References\n\nEntry.');
  });

  it('leaves a fence in a quotation: the blank line ends it', () => {
    expect(close('> ```\n> code\n')).toBe('> ```\n> code\n\n## References\n\nEntry.');
  });
});
