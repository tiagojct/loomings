// ========================================
// Loomings — repair of a CSL entry
// A `references:` entry comes from a document or a share link, so a field can
// have any shape. Citeproc throws on many wrong shapes, and which ones depend
// on the style. This file repairs the entry before citeproc reads it. A number
// becomes text. A field that cannot be repaired is removed, so one bad field
// does not lose the entry.
// Pure: no DOM, no Node or browser APIs (a worker and JavaScriptCore run it).
// ========================================

/** @typedef {import('./bib.js').CslItem} CslItem */

const NAME_FIELDS = new Set([
  'author', 'chair', 'collection-editor', 'compiler', 'composer', 'container-author', 'contributor', 'curator',
  'director', 'editor', 'editor-translator', 'editorial-director', 'executive-producer', 'guest', 'host',
  'illustrator', 'interviewer', 'narrator', 'organizer', 'original-author', 'performer', 'producer', 'recipient',
  'reviewed-author', 'script-writer', 'series-creator', 'translator',
]);
const DATE_FIELDS = new Set(['accessed', 'available-date', 'container', 'event-date', 'issued', 'original-date', 'submitted']);
const DATE_TEXT = ['raw', 'literal', 'season', 'circa'];

const isObject = (/** @type {unknown} */ v) => typeof v === 'object' && v !== null && !Array.isArray(v);

/**
 * @param {unknown} value
 * @returns {string|undefined}
 */
function toText(value) {
  if (typeof value === 'string') return value;
  return typeof value === 'number' && Number.isFinite(value) ? String(value) : undefined;
}

/**
 * Keeps the text fields of an object. Other fields are removed.
 *
 * @param {Record<string, unknown>} value
 * @param {string[]} [only]  the fields to keep; all if not given
 * @returns {Record<string, string>}
 */
function textFields(value, only) {
  /** @type {[string, string][]} */
  const kept = [];
  for (const [key, field] of Object.entries(value)) {
    const text = toText(field);
    if (text !== undefined && (!only || only.includes(key))) kept.push([key, text]);
  }
  return Object.fromEntries(kept);
}

/**
 * @param {unknown} value
 * @returns {Record<string, string>[]|undefined}
 */
function repairNames(value) {
  if (!Array.isArray(value)) return undefined;
  const names = value.filter(isObject).map((name) => textFields(name)).filter((name) => Object.keys(name).length > 0);
  return names.length ? names : undefined;
}

/** True for a part of a date: a year, month or day. */
const isDatePart = (/** @type {unknown} */ v) =>
  (typeof v === 'number' && Number.isFinite(v)) || (typeof v === 'string' && /^-?\d+$/.test(v));

/**
 * @param {unknown} value
 * @returns {Record<string, unknown>|undefined}
 */
function repairDate(value) {
  if (!isObject(value)) return undefined;
  const date = /** @type {Record<string, unknown>} */ (value);
  /** @type {Record<string, unknown>} */
  const out = textFields(date, DATE_TEXT);
  const parts = date['date-parts'];
  const valid = Array.isArray(parts) && parts.length > 0
    && parts.every((p) => Array.isArray(p) && p.length > 0 && p.every(isDatePart));
  if (valid) out['date-parts'] = parts;
  return Object.keys(out).length ? out : undefined;
}

/**
 * @param {CslItem} item
 * @returns {CslItem}
 */
export function sanitiseItem(item) {
  /** @type {[string, unknown][]} */
  const kept = [];
  for (const [key, value] of Object.entries(item)) {
    const repaired = NAME_FIELDS.has(key) ? repairNames(value) : DATE_FIELDS.has(key) ? repairDate(value) : toText(value);
    if (repaired !== undefined) kept.push([key, repaired]);
  }
  return /** @type {CslItem} */ (Object.fromEntries(kept));
}
