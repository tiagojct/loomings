// ========================================
// Loomings — citation library
// Turns the citation keys of a document's frontmatter and the stored files
// into the sources for the citation session.
// Pure: the bundled assets come in as an argument.
// ========================================

import { checkStyle, DEFAULT_LOCALE, DEFAULT_STYLE, fileBaseName as baseName } from './style.js';

// Parent ids of dependent styles that a bundled style stands in for.
const PARENT_ALIASES = { 'nlm-citation-sequence': 'vancouver', 'nlm-citation-sequence-brackets': 'vancouver' };

/**
 * @typedef {{name: string, kind: 'bib'|'csl', text: string}} StoredFile
 * @typedef {{loadBundledStyle(id: string): Promise<string|null>,
 *   loadLocale(lang: string|null|undefined): Promise<{lang: string, xml: string}>}} CitationAssets
 */

/**
 * The XML of the parent of a dependent style: a stored file first, then a
 * bundled style. Only one level is resolved.
 *
 * @param {string} parent
 * @param {StoredFile[]} files
 * @param {CitationAssets} assets
 * @returns {Promise<string|null>}
 */
async function findParent(parent, files, assets) {
  const id = baseName(parent);
  const stored = files.find((f) => f.kind === 'csl' && baseName(f.name) === id);
  if (stored) {
    const checked = checkStyle(stored.text);
    return checked.ok ? stored.text : null;
  }
  return (await assets.loadBundledStyle(id)) ?? (await assets.loadBundledStyle(PARENT_ALIASES[id] ?? '')) ?? null;
}

/**
 * @param {import('./frontmatter.js').CitationMeta} meta
 * @param {StoredFile[]} files
 * @param {CitationAssets} assets
 * @returns {Promise<{bibs: {name: string, text: string}[], styleXml: string|null, localeXml: string|null,
 *   fallbackLocaleXml: string, lang: string, missing: string[], styleError?: string}>}
 */
export async function resolveSources(meta, files, assets) {
  /** @type {string[]} */
  const missing = [];
  const bibFiles = files.filter((f) => f.kind === 'bib');
  const bibs = [];
  for (const entry of meta.bibliography ?? []) {
    const found = bibFiles.find((f) => baseName(f.name) === baseName(entry));
    if (found) {
      if (!bibs.some((b) => b.name === found.name)) bibs.push({ name: found.name, text: found.text });
    }
    else missing.push(entry);
  }

  /** @type {string|null} */
  let styleXml = null;
  /** @type {string|undefined} */
  let styleError;
  const wanted = meta.csl ? baseName(meta.csl) : DEFAULT_STYLE;
  const stored = files.find((f) => f.kind === 'csl' && baseName(f.name) === wanted);
  const bundled = stored ? null : await assets.loadBundledStyle(wanted);
  const candidate = stored ? stored.text : bundled;
  if (candidate == null) {
    missing.push(meta.csl ?? wanted);
    styleError = `The style ${meta.csl ?? wanted} was not found. The default style is ${DEFAULT_STYLE}.`;
  } else {
    // Bundled styles are known to be good. Only a stored file needs the check.
    const checked = stored ? checkStyle(candidate) : null;
    if (!checked || checked.ok) {
      styleXml = candidate;
    } else if (checked.reason === 'dependent') {
      const parent = checked.parent ? await findParent(checked.parent, files, assets) : null;
      if (parent) styleXml = parent;
      else styleError = `This style depends on ${checked.parent ?? 'another style'}. Add that file.`;
    } else {
      styleError = 'The style file is not valid CSL.';
    }
  }
  if (styleXml === null) styleXml = await assets.loadBundledStyle(DEFAULT_STYLE);

  const locale = await assets.loadLocale(meta.lang ?? DEFAULT_LOCALE);
  const fallback = locale.lang === DEFAULT_LOCALE ? locale : await assets.loadLocale(DEFAULT_LOCALE);

  /** @type {any} */
  const out = { bibs, styleXml, localeXml: locale.xml, fallbackLocaleXml: fallback.xml, lang: locale.lang, missing };
  if (styleError) out.styleError = styleError;
  return out;
}
