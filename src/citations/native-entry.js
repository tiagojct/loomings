// ========================================
// Loomings — the citation code for JavaScriptCore
// The native app runs this file as one script, through the global
// `LoomingsCitations`. The session is the same one the web worker runs.
// Each function takes and gives text: Swift passes the strings, and each
// result is JSON. An error stays a JavaScript exception, and Swift catches it.
// ========================================

import { readCitationMeta, setCitationMeta } from './frontmatter.js';
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
 * @param {string} xml
 * @returns {string}  the result of checkStyle as JSON
 */
export function checkStyle(xml) {
  return JSON.stringify(check(xml));
}
