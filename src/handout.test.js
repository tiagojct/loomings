import { describe, it, expect } from 'vitest';
import { handoutCss, paperFor } from './handout.js';
import { roles } from './palettes.js';

describe('handout page', () => {
  it('uses Letter where the native app does, A4 elsewhere', () => {
    expect(paperFor('en-US')).toBe('letter');
    expect(paperFor('en')).toBe('letter');
    expect(paperFor('en-GB')).toBe('A4');
    expect(paperFor('pt-PT')).toBe('A4');
    expect(paperFor('pt')).toBe('A4');
    expect(paperFor('not a locale')).toBe('A4');
  });

  it('numbers pages "Title · page N of M", with the title escaped', () => {
    const css = handoutCss({ title: 'A "quoted" \\ title\nnext', palette: roles('pequod', 'light'), paper: 'A4' });
    expect(css).toContain('size: A4;');
    expect(css).toContain('content: "A \\"quoted\\" \\\\ title next \\00B7  page " counter(page) " of " counter(pages);');
    expect(handoutCss({ title: '', palette: roles('pequod', 'light'), paper: 'letter' }))
      .toContain('content: "page " counter(page) " of " counter(pages);');
  });

  it("prints in the family's light colours", () => {
    const p = roles('pequod', 'light');
    const css = handoutCss({ title: 'T', palette: p, paper: 'A4' });
    expect(css).toContain(`--print-fg: ${p.fg};`);
    expect(css).toContain(`--print-heading: ${p.heading};`);
    expect(css).toContain(`--print-link: ${p.accent};`);
    expect(css).toMatch(/@media print \{ :root \{/);
  });
});
