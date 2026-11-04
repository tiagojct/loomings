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

export const DEFAULT_STYLE = 'chicago-author-date';
export const BUNDLED_LOCALES = ['en-US', 'en-GB', 'pt-PT', 'es-ES'];
export const DEFAULT_LOCALE = 'en-US';

/**
 * The name that matches a frontmatter value to a stored or bundled file: no
 * folders, no .bib or .csl ending, lower case.
 *
 * @param {unknown} value
 * @returns {string}
 */
export function fileBaseName(value) {
  return (String(value).split(/[\\/]/).pop() ?? '').replace(/\.(bib|csl)$/i, '').trim().toLowerCase();
}

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
 * Checks that the tags are balanced and that the root is a closed style.
 * A small tokenizer: no DOM, so a worker and JavaScriptCore can run it.
 *
 * @param {string} xml
 * @returns {boolean}
 */
function wellFormed(xml) {
  const text = xml
    .replace(/<!--[\s\S]*?-->/g, '')
    .replace(/<!\[CDATA\[[\s\S]*?\]\]>/g, '')
    .replace(/<\?[\s\S]*?\?>/g, '')
    .replace(/<!DOCTYPE[^>]*>/gi, '');
  const TAG = /<(\/?)([A-Za-z_][^\s/>]*)((?:"[^"]*"|'[^']*'|[^>"'])*?)(\/?)>/g;
  /** @type {string[]} */
  const stack = [];
  let last = 0;
  let closedRoot = false;
  let m;
  while ((m = TAG.exec(text)) !== null) {
    // Text between tags must not contain a stray "<".
    if (text.slice(last, m.index).includes('<')) return false;
    last = TAG.lastIndex;
    if (closedRoot) return false;
    if (m[1]) {
      if (stack.pop() !== m[2]) return false;
      if (!stack.length) closedRoot = true;
    } else if (!m[4]) {
      stack.push(m[2]);
    } else if (!stack.length) {
      closedRoot = true;
    }
  }
  if (text.slice(last).includes('<')) return false;
  return closedRoot && /^style$/.test(text.match(/<([A-Za-z_][^\s/>]*)/)?.[1] ?? '');
}

/**
 * @param {string} xml
 * @returns {{ok: true, title: string} | {ok: false, reason: 'invalid'|'dependent', parent?: string}}
 */
export function checkStyle(xml) {
  if (typeof xml !== 'string' || !/<style[\s>]/.test(xml) || !wellFormed(xml)) return { ok: false, reason: 'invalid' };
  const parent = /<link\b[^>]*\brel\s*=\s*["']independent-parent["'][^>]*>/.exec(xml);
  if (parent) {
    const href = /\bhref\s*=\s*["']([^"']*)["']/.exec(parent[0]);
    const id = href ? href[1].replace(/\/+$/, '').split('/').pop() : undefined;
    return id ? { ok: false, reason: 'dependent', parent: id } : { ok: false, reason: 'dependent' };
  }
  const info = /<info[\s>][\s\S]*?<\/info>/.exec(xml);
  if (!info || !/<citation[\s>]/.test(xml)) return { ok: false, reason: 'invalid' };
  const title = /<title[^>]*>([\s\S]*?)<\/title>/.exec(info[0]);
  const text = title ? title[1].replace(/<[^>]*>/g, '').trim() : '';
  return { ok: true, title: text };
}
