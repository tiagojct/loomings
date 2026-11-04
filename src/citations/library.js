// ========================================
// Loomings — citation library
// Turns the citation keys of a document's frontmatter and the stored files
// into the sources for the citation session.
// Pure: the bundled assets come in as an argument.
// ========================================

import { BUNDLED_STYLES, checkStyle, DEFAULT_LOCALE, DEFAULT_STYLE, fileBaseName as baseName, localeFor } from './style.js';

// Parent ids of dependent styles that a bundled style stands in for.
const PARENT_ALIASES = /** @type {Record<string, string>} */ ({
  'nlm-citation-sequence': 'vancouver',
  'nlm-citation-sequence-brackets': 'vancouver',
});

/**
 * @typedef {{name: string, kind: 'bib'|'csl', text: string}} StoredFile
 * @typedef {{loadBundledStyle(id: string): Promise<string|null>,
 *   loadLocale(lang: string|null|undefined): Promise<{lang: string, xml: string}>}} CitationAssets
 * @typedef {{bibs: StoredFile[], unfound: string[], style: {file: StoredFile}|{id: string}, parent?: string,
 *   missing: string[], styleError?: string, styleNote?: string}} SourcePlan
 *   `unfound` holds the bibliography entries with no file. `parent` is the
 *   parent of a dependent style, also when the style comes from another file.
 *   With `styleError`, the citations stay literal. With `styleNote`, the
 *   default style formats them and the note says so.
 */

const isBundled = (/** @type {string} */ id) => BUNDLED_STYLES.some((s) => s.id === id);

/** The web keeps files with no folder, so a frontmatter value matches by base name. */
const sameBaseName = (/** @type {{name: string}} */ file, /** @type {string} */ entry) =>
  baseName(file.name) === baseName(entry);

/**
 * The style for the parent of a dependent style: a stored file first, then a
 * bundled style. Only one level is resolved.
 *
 * @param {string} parent
 * @param {StoredFile[]} files
 * @returns {{file: StoredFile}|{id: string}|null}
 */
function findParent(parent, files) {
  const id = baseName(parent);
  const stored = files.find((f) => f.kind === 'csl' && baseName(f.name) === id);
  if (stored) return checkStyle(stored.text).ok ? { file: stored } : null;
  const bundled = [id, PARENT_ALIASES[id]].find((candidate) => candidate && isBundled(candidate));
  return bundled ? { id: bundled } : null;
}

/**
 * Which files and which style a document uses, from the files that are known.
 * The web and the native app both follow this plan.
 *
 * @param {{bibliography?: string[], csl?: string|null}} meta
 * @param {StoredFile[]} files
 * @param {(file: StoredFile, entry: string) => boolean} [sameFile]  true when a frontmatter value names this file
 * @returns {SourcePlan}
 */
export function planSources(meta, files, sameFile = sameBaseName) {
  /** @type {string[]} */
  const unfound = [];
  const bibFiles = files.filter((f) => f.kind === 'bib');
  /** @type {StoredFile[]} */
  const bibs = [];
  for (const entry of meta.bibliography ?? []) {
    const found = bibFiles.find((f) => sameFile(f, entry));
    if (!found) unfound.push(entry);
    else if (!bibs.includes(found)) bibs.push(found);
  }

  const missing = [...unfound];
  /** @type {{file: StoredFile}|{id: string}|null} */
  let style = null;
  /** @type {string|undefined} */
  let parent;
  /** @type {string|undefined} */
  let styleError;
  /** @type {string|undefined} */
  let styleNote;
  const wanted = meta.csl ? baseName(meta.csl) : DEFAULT_STYLE;
  const stored = files.find((f) => f.kind === 'csl' && sameFile(f, meta.csl ?? DEFAULT_STYLE));
  if (stored) {
    const checked = checkStyle(stored.text);
    if (checked.ok) {
      style = { file: stored };
    } else if (checked.reason === 'dependent') {
      parent = checked.parent;
      style = parent ? findParent(parent, files) : null;
      if (!style) styleError = `This style depends on ${parent ?? 'another style'}. Add that file.`;
    } else {
      styleError = 'The style file is not valid CSL.';
    }
  } else if (isBundled(wanted)) {
    // Bundled styles are known to be good. Only a stored file needs the check.
    style = { id: wanted };
  } else {
    missing.push(meta.csl ?? wanted);
    styleNote = `The style ${meta.csl ?? wanted} was not found. The default style is ${DEFAULT_STYLE}.`;
  }
  /** @type {SourcePlan} */
  const plan = { bibs, unfound, style: style ?? { id: DEFAULT_STYLE }, missing };
  if (parent) plan.parent = parent;
  if (styleError) plan.styleError = styleError;
  if (styleNote) plan.styleNote = styleNote;
  return plan;
}

/**
 * @param {import('./frontmatter.js').CitationMeta} meta
 * @param {StoredFile[]} files
 * @param {CitationAssets} assets
 * @returns {Promise<{bibs: {name: string, text: string}[], styleXml: string|null, localeXml: string|null,
 *   fallbackLocaleXml: string, lang: string, missing: string[], styleError?: string, styleNote?: string}>}
 */
export async function resolveSources(meta, files, assets) {
  const plan = planSources(meta, files);
  const styleXml = 'file' in plan.style ? plan.style.file.text : await assets.loadBundledStyle(plan.style.id);
  const locale = await assets.loadLocale(meta.lang ?? DEFAULT_LOCALE);
  const fallback = locale.lang === DEFAULT_LOCALE ? locale : await assets.loadLocale(DEFAULT_LOCALE);

  /** @type {any} */
  const out = {
    bibs: plan.bibs.map(({ name, text }) => ({ name, text })),
    styleXml,
    localeXml: locale.xml,
    fallbackLocaleXml: fallback.xml,
    lang: locale.lang,
    missing: plan.missing,
  };
  if (plan.styleError) out.styleError = plan.styleError;
  if (plan.styleNote) out.styleNote = plan.styleNote;
  return out;
}

/**
 * @typedef {{files?: {name: string, kind: 'bib'|'csl', text?: string}[], tried?: string[],
 *   unreadable?: string[], noFolder?: boolean, allowPaths?: boolean}} NativeFiles
 *   What the native app knows so far. `files` are the files it read, each named
 *   as a plan asked for it (a style file carries its text). `tried` holds each
 *   name it tried, and `unreadable` the names of files it found but could not
 *   read as text. `noFolder` is true for a document with no folder.
 *   `allowPaths` is false for a document from a share link that is not saved:
 *   the writer of the link chose its names, so no name can leave the folder.
 * @typedef {{bibFiles: string[], stylePath: string|null, styleId: string|null, lang: string,
 *   fallbackLang: string, missing: string[], missingNotes: Record<string, string>,
 *   styleError?: string, styleNote?: string, ignoredPaths: string[], done: boolean}} NativePlan
 *   While `done` is false, the app reads each name that it has not tried, and
 *   asks again. When `done` is true, `bibFiles` are the files in use, and the
 *   style is the file `stylePath`, or else the bundled style `styleId`.
 *   `ignoredPaths` holds the values that the plan did not follow.
 */

/** @param {string} name  @param {string} ending  added to a name with no ending */
const withEnding = (name, ending) => (/\.[^./\\]+$/.test(name) ? name : `${name}${ending}`);

/** @param {string} name  a path as the frontmatter writes it */
const isRelative = (name) => !/^(?:[\\/~]|[A-Za-z]:)/.test(name);

/** @param {string} name  True for a path that can leave the folder of the document. */
const leavesFolder = (name) => !isRelative(name) || /(?:^|[\\/])\.\.(?:[\\/]|$)/.test(name);

/** The name of a file in the folder of another file. */
const sibling = (/** @type {string} */ path, /** @type {string} */ name) =>
  `${path.slice(0, Math.max(path.lastIndexOf('/'), path.lastIndexOf('\\')) + 1)}${name}`;

/**
 * The next step for the native app. It reads by path, so a value names one
 * path: `a/refs.bib` and `b/refs.bib` are two files, and an absent path is
 * missing also when another file has its base name. A style file wins over a
 * bundled style of the same name, as a stored file does on the web.
 *
 * @param {{bibliography?: string[], csl?: string|null, lang?: string|null}} meta
 * @param {NativeFiles} known
 * @returns {NativePlan}
 */
export function planNativeSources(meta, known) {
  const { tried = [], unreadable = [], noFolder = false, allowPaths = true } = known;
  const ignored = (/** @type {string|null|undefined} */ name) => !allowPaths && Boolean(name) && leavesFolder(/** @type {string} */ (name));
  const ignoredPaths = [...(meta.bibliography ?? []), meta.csl].filter(ignored);
  const usable = {
    ...meta,
    bibliography: (meta.bibliography ?? []).filter((entry) => !ignored(entry)),
    csl: ignored(meta.csl) ? null : meta.csl,
  };
  const files = /** @type {StoredFile[]} */ ((known.files ?? []).map((f) => ({ ...f, text: f.text ?? '' })));
  const bibName = (/** @type {string} */ entry) => withEnding(entry, '.bib');
  const styleName = (/** @type {string} */ entry) => withEnding(entry, '.csl');
  /** @type {(file: StoredFile, entry: string) => boolean} */
  const samePath = (file, entry) => file.name === (file.kind === 'bib' ? bibName(entry) : styleName(entry));
  const plan = planSources(usable, files, samePath);

  const unread = plan.unfound.filter((entry) => !tried.includes(bibName(entry)));
  const unfound = plan.unfound.filter((entry) => !unread.includes(entry));
  const usedFile = 'file' in plan.style ? plan.style.file.name : null;
  const { csl } = usable;
  const storedStyle = csl ? files.find((f) => f.kind === 'csl' && samePath(f, csl)) : null;

  /** @type {string|null} */
  let nextStyle = null;
  if (csl && !storedStyle) nextStyle = styleName(csl);
  else if (plan.parent && storedStyle && !usedFile) nextStyle = sibling(storedStyle.name, `${baseName(plan.parent)}.csl`);
  if (nextStyle && tried.includes(nextStyle)) nextStyle = null;

  const missing = [...unfound, ...plan.missing.slice(plan.unfound.length)];
  /** @type {Record<string, string>} */
  const missingNotes = {};
  for (const name of missing) {
    if (unreadable.includes(bibName(name)) || unreadable.includes(styleName(name))) {
      missingNotes[name] = `The file ${name} could not be read as text.`;
    } else if (noFolder && isRelative(name)) {
      missingNotes[name] = `The file ${name} is missing. This document has no folder. Save the document, or use an absolute path.`;
    }
  }

  const stylePath = nextStyle ?? usedFile;
  /** @type {NativePlan} */
  const out = {
    bibFiles: [...plan.bibs.map((f) => f.name), ...unread.map(bibName)],
    stylePath,
    styleId: stylePath || !('id' in plan.style) ? null : plan.style.id,
    lang: localeFor(meta.lang ?? DEFAULT_LOCALE),
    fallbackLang: DEFAULT_LOCALE,
    missing,
    missingNotes,
    ignoredPaths: /** @type {string[]} */ (ignoredPaths),
    done: unread.length === 0 && nextStyle === null,
  };
  if (plan.styleError && !nextStyle) out.styleError = plan.styleError;
  if (plan.styleNote && !nextStyle) out.styleNote = plan.styleNote;
  return out;
}
