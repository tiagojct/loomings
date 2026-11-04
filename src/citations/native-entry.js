// ========================================
// Loomings — the citation code for JavaScriptCore
// The native app runs this file as one script, through the global
// `LoomingsCitations`. The session is the same one the web worker runs.
// Each function takes and gives text: Swift passes the strings, and each
// result is JSON. An error stays a JavaScript exception, and Swift catches it.
// ========================================

import { readCitationMeta, setCitationMeta } from './frontmatter.js';
import { planNativeSources } from './library.js';
import { fileChange as changeFor } from './panel.js';
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
