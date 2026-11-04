// ========================================
// Loomings — the citation code for JavaScriptCore
// The native app runs this file as one script, through the global
// `LoomingsCitations`. The session is the same one the web worker runs.
// Each function takes and gives text: Swift passes the strings, and each
// result is JSON. An error stays a JavaScript exception, and Swift catches it.
// ========================================

import { readCitationMeta, setCitationMeta } from './frontmatter.js';
import { planNativeSources } from './library.js';
import {
  choiceIsOn, fileChange as changeFor, insertCitation as insertionFor, languageChoices, styleChoices, withBibliography,
} from './panel.js';
import { createSession } from './session.js';
import { checkStyle as check } from './style.js';

const session = createSession();

/** @param {string} json  the fields of CitationSources (session.js) */
export function setSources(json) {
  session.setSources(JSON.parse(json));
}

/**
 * @param {string} source
 * @returns {string}  a CitationReport as JSON
 */
export function analyse(source) {
  return JSON.stringify(session.analyse(source));
}

/**
 * @param {string} source
 * @returns {string}  a CitationMeta as JSON
 */
export function readMeta(source) {
  return JSON.stringify(readCitationMeta(source));
}

/**
 * @param {string} source
 * @param {'bibliography'|'csl'|'references'} key
 * @param {string|null} value  null removes the key
 * @returns {string}  the changed text as a JSON string
 */
export function setMeta(source, key, value) {
  return JSON.stringify(setCitationMeta(source, key, value));
}

/**
 * @param {string} source
 * @param {string} name  the missing name
 * @param {string} path  the file that takes its place
 * @returns {string}  the key and the value for `setMeta` as JSON
 */
export function fileChange(source, name, path) {
  return JSON.stringify(changeFor(readCitationMeta(source), name, path));
}

/**
 * Adds a chosen file to `bibliography`. A file that is in the list changes
 * nothing.
 *
 * @param {string} source
 * @param {string} path
 * @returns {string}  the changed text as a JSON string
 */
export function addBibliography(source, path) {
  const { bibliography } = readCitationMeta(source);
  if (bibliography.includes(path)) return JSON.stringify(source);
  return JSON.stringify(setCitationMeta(source, 'bibliography', withBibliography(bibliography, path)));
}

/** @param {import('./frontmatter.js').CitationMeta} meta */
const nativeStyleChoices = (meta) => styleChoices(meta, [], { exact: true });

/**
 * The checked items of the References menu.
 *
 * @param {string} source
 * @returns {string}  JSON with `style`, a bundled style or null for a style
 *   file, and `language`
 */
export function referenceChoices(source) {
  const meta = readCitationMeta(source);
  return JSON.stringify({
    style: nativeStyleChoices(meta).find((choice) => choice.checked)?.value ?? null,
    language: languageChoices(meta).find((choice) => choice.checked)?.value ?? null,
  });
}

/**
 * One choice of the Citation Style or the Language menu.
 *
 * @param {string} source
 * @param {'csl'|'lang'} key
 * @param {string} value
 * @returns {string}  the changed text as a JSON string
 */
export function setChoice(source, key, value) {
  const meta = readCitationMeta(source);
  const choices = key === 'csl' ? nativeStyleChoices(meta) : languageChoices(meta);
  return JSON.stringify(choiceIsOn(choices, value) ? source : setCitationMeta(source, key, value));
}

/**
 * The text to insert for a key, by the rule of the web's References view.
 *
 * @param {string} source
 * @param {number} position  the end of the selection, in UTF-16 units
 * @param {string} key
 * @returns {string}  the fields `insert` and `from` as JSON
 */
export function insertCitation(source, position, key) {
  return JSON.stringify(insertionFor(source, position, key));
}

/**
 * @param {string} xml
 * @returns {string}  the result of checkStyle as JSON
 */
export function checkStyle(xml) {
  return JSON.stringify(check(xml));
}

/**
 * The next step to find the files of a document. Swift only reads what the
 * plan names, so the rules for names stay in one place.
 *
 * @param {string} metaJson  the fields `bibliography`, `csl` and `lang`
 * @param {string} knownJson  a NativeFiles (library.js)
 * @returns {string}  a NativePlan as JSON
 */
export function resolveNative(metaJson, knownJson) {
  return JSON.stringify(planNativeSources(JSON.parse(metaJson), JSON.parse(knownJson)));
}
