// ========================================
// Loomings — bundled CSL assets (web only)
// Each style and locale file is a lazy chunk. The native app reads the same
// files from disk. This is the only citation file that uses Vite.
// ========================================

import { BUNDLED_LOCALES, localeFor } from './style.js';

export { BUNDLED_STYLES, BUNDLED_LOCALES, localeFor } from './style.js';

const styles = import.meta.glob('./styles/*.csl', { query: '?raw', import: 'default' });
const locales = import.meta.glob('./locales/*.xml', { query: '?raw', import: 'default' });

/**
 * @param {string} id a bundled style id
 * @returns {Promise<string|null>}
 */
export async function loadBundledStyle(id) {
  const load = styles[`./styles/${id}.csl`];
  return load ? /** @type {string} */ (await load()) : null;
}

/**
 * @param {string|null|undefined} lang any language tag
 * @returns {Promise<{lang: string, xml: string}>}
 */
export async function loadLocale(lang) {
  const tag = BUNDLED_LOCALES.includes(/** @type {string} */ (lang)) ? /** @type {string} */ (lang) : localeFor(lang);
  const xml = /** @type {string} */ (await locales[`./locales/locales-${tag}.xml`]());
  return { lang: tag, xml };
}
