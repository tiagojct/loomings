// ========================================
// Loomings — citation style lists and checks
// Bundled style and locale ids, the locale fallback and a cheap style check.
// Pure: no DOM, no Node or browser APIs (a worker and JavaScriptCore run it).
// ========================================

export const BUNDLED_STYLES = [
  { id: 'chicago-author-date', title: 'Chicago (author-date)' },
  { id: 'apa', title: 'APA' },
  { id: 'vancouver', title: 'Vancouver' },
  { id: 'american-medical-association', title: 'AMA' },
  { id: 'ieee', title: 'IEEE' },
];

export const BUNDLED_LOCALES = ['en-US', 'en-GB', 'pt-PT', 'es-ES'];
export const DEFAULT_LOCALE = 'en-US';

/**
 * Chooses the bundled locale for a language tag. An exact match wins. Then
 * the first bundled locale with the same language prefix. Then en-US.
 *
 * @param {string|null|undefined} lang
 * @returns {string}
 */
export function localeFor(lang) {
  if (typeof lang !== 'string' || !lang.trim()) return DEFAULT_LOCALE;
  const tag = lang.trim().replace(/_/g, '-').toLowerCase();
  const exact = BUNDLED_LOCALES.find((l) => l.toLowerCase() === tag);
  if (exact) return exact;
  const prefix = tag.split('-')[0];
  // Other English variants follow British usage. Plain "en" is en-US.
  if (prefix === 'en') return tag === 'en' ? DEFAULT_LOCALE : 'en-GB';
  return BUNDLED_LOCALES.find((l) => l.toLowerCase().split('-')[0] === prefix) ?? DEFAULT_LOCALE;
}

/**
 * @param {string} xml
 * @returns {{ok: true, title: string} | {ok: false, reason: 'invalid'|'dependent', parent?: string}}
 */
export function checkStyle(xml) {
  if (typeof xml !== 'string' || !/<style[\s>]/.test(xml)) return { ok: false, reason: 'invalid' };
  const parent = /<link\b[^>]*\brel\s*=\s*["']independent-parent["'][^>]*>/.exec(xml);
  if (parent) {
    const href = /\bhref\s*=\s*["']([^"']*)["']/.exec(parent[0]);
    const id = href ? href[1].replace(/\/+$/, '').split('/').pop() : undefined;
    return id ? { ok: false, reason: 'dependent', parent: id } : { ok: false, reason: 'dependent' };
  }
  const info = /<info[\s>][\s\S]*?<\/info>/.exec(xml);
  const title = info && /<title[^>]*>([\s\S]*?)<\/title>/.exec(info[0]);
  const text = title ? title[1].replace(/<[^>]*>/g, '').trim() : '';
  return { ok: true, title: text };
}
