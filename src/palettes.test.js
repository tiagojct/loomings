import { describe, it, expect } from 'vitest';
import { PALETTES, PALETTE_KEYS, FAMILY_ORDER, DEFAULT_FAMILY, roles, cssVars, contrast } from './palettes.js';

const HEX = /^#[0-9a-f]{6}$/i;

describe('palettes', () => {
  it('lists every family in FAMILY_ORDER exactly once', () => {
    expect([...FAMILY_ORDER].sort()).toEqual(Object.keys(PALETTES).sort());
    expect(new Set(FAMILY_ORDER).size).toBe(FAMILY_ORDER.length);
    expect(PALETTES[DEFAULT_FAMILY]).toBeDefined();
  });

  for (const family of Object.keys(PALETTES)) {
    describe(family, () => {
      it('has a label and named dark/light modes', () => {
        expect(PALETTES[family].label).toBeTruthy();
        expect(PALETTES[family].modes.dark).toBeTruthy();
        expect(PALETTES[family].modes.light).toBeTruthy();
      });

      for (const mode of ['dark', 'light']) {
        it(`${mode}: defines every key as a 6-digit hex`, () => {
          const p = PALETTES[family][mode];
          for (const k of PALETTE_KEYS) expect(p[k], k).toMatch(HEX);
          for (const k of ['heading', 'emphasis', 'code', 'marker']) if (p[k]) expect(p[k], k).toMatch(HEX);
        });

        it(`${mode}: body text and ink roles clear WCAG floors on the page background`, () => {
          const r = roles(family, mode);
          expect(contrast(r.fg, r.bg), 'fg/bg').toBeGreaterThanOrEqual(7);
          expect(contrast(r.fgDim, r.bg), 'fgDim/bg').toBeGreaterThanOrEqual(4.5);
          expect(contrast(r.fgGhost, r.bg), 'fgGhost/bg').toBeGreaterThanOrEqual(2); // placeholders and hints only
          expect(contrast(r.heading, r.bg), 'heading/bg').toBeGreaterThanOrEqual(3);
          expect(contrast(r.accent, r.bg), 'accent/bg').toBeGreaterThanOrEqual(3);
          expect(contrast(r.fg, r.bgDeep), 'fg/bgDeep').toBeGreaterThanOrEqual(4.5);
        });

        it(`${mode}: background is on the right side of mid-grey`, () => {
          const dark = contrast(PALETTES[family][mode].bg, '#000000') < contrast(PALETTES[family][mode].bg, '#ffffff');
          expect(dark).toBe(mode === 'dark');
        });

        it(`${mode}: cssVars covers the properties style.css reads`, () => {
          const vars = cssVars(family, mode);
          for (const name of ['--bg', '--bg-elev', '--bg-deep', '--fg', '--fg-dim', '--fg-ghost',
                              '--accent', '--accent-light', '--accent-dim', '--border',
                              '--heading', '--emphasis', '--code', '--marker']) {
            expect(vars[name], name).toMatch(HEX);
          }
        });
      }
    });
  }

  it('contrast() matches the WCAG reference pair', () => {
    expect(contrast('#000000', '#ffffff')).toBeCloseTo(21, 5);
    expect(contrast('#777777', '#ffffff')).toBeCloseTo(4.48, 2);
  });
});
