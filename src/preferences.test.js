import { describe, it, expect } from 'vitest';
import { WIDTHS, FONT_MIN, FONT_MAX, nextFontSize, nextWidth } from './preferences.js';

describe('writing preferences', () => {
  it('clamps the font size to the editor range', () => {
    expect(nextFontSize(15, 1, false)).toBe(16);
    expect(nextFontSize(FONT_MAX, 1, false)).toBe(FONT_MAX);
    expect(nextFontSize(FONT_MIN, -1, false)).toBe(FONT_MIN);
  });

  it('cycles column widths in order', () => {
    expect(WIDTHS).toEqual(['wide', 'normal', 'narrow']);
    expect(nextWidth('wide', false)).toBe('normal');
    expect(nextWidth('normal', false)).toBe('narrow');
    expect(nextWidth('narrow', false)).toBe('wide');
  });

  it('does not change a preference while projector mode is on', () => {
    expect(nextFontSize(15, 1, true)).toBeNull();
    expect(nextWidth('wide', true)).toBeNull();
  });
});
