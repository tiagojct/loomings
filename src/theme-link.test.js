import { describe, it, expect } from 'vitest';
import { readThemeParams, withoutThemeParams } from './theme-link.js';

const FAMILIES = ['pequod', 'goney', 'bachelor'];

describe('theme deep links', () => {
  it('reads a family and a mode the app knows', () => {
    expect(readThemeParams('?theme=goney', { families: FAMILIES, modes: ['system', 'light', 'dark'] }))
      .toEqual({ family: 'goney', mode: null, present: true });

    expect(readThemeParams('?theme=bachelor&mode=dark', { families: FAMILIES, modes: ['system', 'light', 'dark'] }))
      .toEqual({ family: 'bachelor', mode: 'dark', present: true });
  });

  it('ignores a family or mode it does not know, but still reports the link', () => {
    expect(readThemeParams('?theme=unicorn&mode=sepia', { families: FAMILIES, modes: ['system', 'light', 'dark'] }))
      .toEqual({ family: null, mode: null, present: true });
  });

  it('reports nothing for a URL with no theme parameters', () => {
    expect(readThemeParams('', { families: FAMILIES, modes: ['system', 'light', 'dark'] }))
      .toEqual({ family: null, mode: null, present: false });
    expect(readThemeParams('?lesson=basics', { families: FAMILIES, modes: ['system', 'light', 'dark'] }))
      .toEqual({ family: null, mode: null, present: false });
  });

  it('strips theme parameters while keeping the lesson and the hash', () => {
    expect(withoutThemeParams('https://loomings.tiagojacinto.eu/app/?lesson=basics&theme=goney&mode=dark'))
      .toBe('/app/?lesson=basics');
    expect(withoutThemeParams('https://loomings.tiagojacinto.eu/app/?theme=goney#d=z.abc'))
      .toBe('/app/#d=z.abc');
  });

  it('leaves a URL without theme parameters alone', () => {
    const href = 'https://loomings.tiagojacinto.eu/app/?lesson=basics';
    expect(withoutThemeParams(href)).toBe(href);
  });
});
