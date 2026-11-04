// ========================================
// Loomings — citation library
// Turns the citation keys of a document's frontmatter and the stored files
// into the sources for the citation session.
// Pure: the bundled assets come in as an argument.
// ========================================

import { checkStyle, DEFAULT_LOCALE } from './style.js';

const DEFAULT_STYLE = 'chicago-author-date';

/**
 * @typedef {{name: string, kind: 'bib'|'csl', text: string}} StoredFile
 * @typedef {{loadBundledStyle(id: string): Promise<string|null>,
 *   loadLocale(lang: string|null|undefined): Promise<{lang: string, xml: string}>}} CitationAssets
 */

/** The file name without folders and without a .bib or .csl ending, in lower case. */
function baseName(value) {
  return (String(value).split(/[\\/]/).pop() ?? '').replace(/\.(bib|csl)$/i, '').trim().toLowerCase();
}

/**
 * @param {import('./frontmatter.js').CitationMeta} meta
 * @param {StoredFile[]} files
 * @param {CitationAssets} assets
 * @returns {Promise<{bibs: {name: string, text: string}[], styleXml: string|null, localeXml: string|null,
 *   fallbackLocaleXml: string|null, lang: string, missing: string[], styleError?: string}>}
 */
export async function resolveSources(meta, files, assets) {
  /** @type {string[]} */
  const missing = [];
  const bibFiles = files.filter((f) => f.kind === 'bib');
  const bibs = [];
  for (const entry of meta.bibliography ?? []) {
    const found = bibFiles.find((f) => baseName(f.name) === baseName(entry));
    if (found) bibs.push({ name: found.name, text: found.text });
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
    styleError = `The style ${meta.csl} was not found. The default style is ${DEFAULT_STYLE}.`;
  } else {
    // Bundled styles are known to be good. Only a stored file needs the check.
    const checked = stored ? checkStyle(candidate) : null;
    if (!checked || checked.ok) {
      styleXml = candidate;
    } else if (checked.reason === 'dependent') {
      styleError = `This style depends on ${checked.parent ?? 'another style'}. Add that file.`;
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
