import { describe, it, expect } from 'vitest';
import { PALETTES, DEFAULT_FAMILY, roles } from './palettes.js';
import { makeHighlight, makeTheme } from './cm-theme.js';

describe('cm-theme', () => {
  const p = roles(DEFAULT_FAMILY, 'dark');

  it('builds a highlight style and a theme for every family and mode', () => {
    for (const family of Object.keys(PALETTES)) {
      for (const mode of ['light', 'dark']) {
        const r = roles(family, mode);
        expect(makeHighlight(r)).toBeTruthy();
        expect(makeTheme(r, mode === 'dark')).toBeTruthy();
      }
    }
  });

  it('colours headings from the palette', () => {
    expect(makeHighlight(p).module?.getRules() ?? '').toContain(p.heading);
  });
});
