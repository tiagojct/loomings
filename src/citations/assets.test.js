import { describe, it, expect } from 'vitest';
import { loadBundledStyle, loadLocale, BUNDLED_STYLES } from './assets.js';
import { checkStyle } from './style.js';

describe('assets', () => {
  it('loads every bundled style as text', async () => {
    for (const s of BUNDLED_STYLES) {
      const xml = await loadBundledStyle(s.id);
      expect(checkStyle(/** @type {string} */ (xml)).ok).toBe(true);
    }
    expect(await loadBundledStyle('nope')).toBe(null);
  });
  it('loads a locale with fallback', async () => {
    const r = await loadLocale('pt-BR');
    expect(r.lang).toBe('pt-PT');
    expect(r.xml).toContain('<locale');
  });
});
