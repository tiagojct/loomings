import { describe, it, expect } from 'vitest';
import { exportHtmlPage, diagramCss, withDiagramStyle } from './export.js';
import { roles } from './palettes.js';

const p = roles('pequod', 'dark');
const lp = roles('pequod', 'light');

describe('exportHtmlPage', () => {
  it('is a standalone page with the palette, the title and the body', () => {
    const html = exportHtmlPage({ title: 'A <b> & "c"', body: '<h1>Hi</h1>', p, lp });
    expect(html.startsWith('<!DOCTYPE html>')).toBe(true);
    expect(html).toContain('<title>A &lt;b&gt; &amp; &quot;c&quot;</title>');
    expect(html).toContain(`background: ${p.bg}; color: ${p.fg};`);
    expect(html).toContain('@media print');
    expect(html).toContain(`.cite-missing { color: ${lp.fgDim}; }`);
    expect(html).toContain('<body>\n<h1>Hi</h1>\n</body>');
    expect(html.endsWith('</html>\n')).toBe(true);
  });
});

describe('diagramCss', () => {
  it('sets the Pele variables for the light palette on white', () => {
    const css = diagramCss(lp);
    expect(css).toContain('--pele-bg:#fff;');
    expect(css).toContain(`--pele-fg:${lp.fg};`);
    expect(css).toContain(`--pele-accent:${lp.accent};`);
    expect(css).not.toContain('"');
  });
});

describe('withDiagramStyle', () => {
  it('adds a style attribute to the root element', () => {
    expect(withDiagramStyle('<svg viewBox="0 0 1 1"><rect/></svg>', '--a:1;')).toBe('<svg style="--a:1;" viewBox="0 0 1 1"><rect/></svg>');
  });
  it('keeps an existing style attribute and does not repeat it', () => {
    const out = withDiagramStyle('<svg style="max-width:100%" viewBox="0 0 1 1"><rect style="fill:red"/></svg>', '--a:1;');
    expect(out).toBe('<svg style="--a:1;;max-width:100%" viewBox="0 0 1 1"><rect style="fill:red"/></svg>');
    expect(out.match(/\sstyle=/g).length).toBe(2);
  });
  it('is not fooled by a greater-than sign in an attribute', () => {
    const out = withDiagramStyle('<svg aria-label="a > b"><rect/></svg>', '--a:1;');
    expect(out).toBe('<svg style="--a:1;" aria-label="a > b"><rect/></svg>');
  });
  it('escapes quotes in the CSS and leaves text with no svg alone', () => {
    expect(withDiagramStyle('<svg>', '--f:"x";')).toBe('<svg style="--f:&#39;x&#39;;">');
    expect(withDiagramStyle('plain', '--a:1;')).toBe('plain');
  });
});
