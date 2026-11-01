// ========================================
// Loomings — frontmatter directives
// `check: <kind> [arguments]` and `limit: <heading> <max>` lines inside the
// leading frontmatter, read and parsed as the native app does
// (macos/Sources/LoomingsTeaching/Directives.swift), with the same notes for
// lines that cannot be understood. Pure: no DOM.
// ========================================

import { splitLines, frontmatterLines } from './parse.js';

/**
 * @typedef {{key: string, value: string, line: number}} Directive  line: 0-based
 * @typedef {{line: number, message: string}} DirectiveNote
 * @typedef {{type: 'heading', level: number|null, min: number}
 *   | {type: 'bulletList'|'orderedList', items: number}
 *   | {type: 'inlineCode'|'link'|'words', min: number}
 *   | {type: 'table', rows: number}
 *   | {type: 'codeBlock', language: string|null}
 *   | {type: 'codeLanguage'|'nestedList'|'quote'|'referenceLink'|'imageAlt'|'emphasis'|'strong'}} Check
 * @typedef {{heading: string, maxWords: number}} SectionLimit
 */

const PATTERN = /^\s*(check|limit)\s*:\s*(.*?)\s*$/i;

/**
 * The check and limit lines of the leading frontmatter, in order.
 *
 * @param {string} source
 * @returns {Directive[]}
 */
export function readDirectives(source) {
  const lines = splitLines(source);
  const frontmatter = frontmatterLines(lines);
  if (!frontmatter) return [];
  /** @type {Directive[]} */
  const directives = [];
  for (let n = 1; n <= frontmatter.last; n++) {
    const m = PATTERN.exec(lines[n].text);
    if (m) directives.push({ key: m[1].toLowerCase(), value: m[2], line: n });
  }
  return directives;
}

/** A positive whole number, as Swift's Int() reads it, or null. */
function positive(text) {
  if (!/^[+-]?\d{1,18}$/.test(text)) return null;
  const value = Number(text);
  return value > 0 ? value : null;
}

/** @param {Directive} directive @param {string} message @returns {{ok: false, note: DirectiveNote}} */
const fail = (directive, message) => ({ ok: false, note: { line: directive.line, message } });

/**
 * @param {Directive} directive
 * @returns {{ok: true, check: Check} | {ok: false, note: DirectiveNote}}
 */
export function parseCheck(directive) {
  const parts = directive.value.split(/\s+/).filter(Boolean);
  if (!parts.length) return fail(directive, 'A check needs a kind, for example "check: heading".');
  const kind = parts[0].toLowerCase();
  const args = parts.slice(1);
  /** @param {Check} check */
  const ok = (check) => ({ ok: /** @type {true} */ (true), check });
  /** @param {Check} check */
  const none = (check) => (args.length ? fail(directive, `"${kind}" takes no number.`) : ok(check));
  /** @param {(n: number) => Check} make @param {number} fallback */
  const counted = (make, fallback) => {
    const value = args.length === 0 ? fallback : args.length === 1 ? positive(args[0]) : null;
    return value === null
      ? fail(directive, `"${kind}" takes one whole number, for example "${kind} ${fallback}".`)
      : ok(make(value));
  };
  switch (kind) {
    case 'heading': {
      const level = args.length > 0 ? positive(args[0]) : null;
      const min = args.length > 1 ? positive(args[1]) : 1;
      if (args.length > 2 || (args.length > 0 && level === null) || min === null) {
        return fail(directive, '"heading" takes a level from 1 to 6 and a count, for example "heading 2".');
      }
      if (level !== null && (level < 1 || level > 6)) return fail(directive, 'A heading level runs from 1 to 6.');
      return ok({ type: 'heading', level, min });
    }
    case 'bullet-list': return counted((items) => ({ type: 'bulletList', items }), 2);
    case 'ordered-list': return counted((items) => ({ type: 'orderedList', items }), 2);
    case 'inline-code': return counted((min) => ({ type: 'inlineCode', min }), 1);
    case 'link': return counted((min) => ({ type: 'link', min }), 1);
    case 'table': return counted((rows) => ({ type: 'table', rows }), 1);
    case 'words': {
      const min = args.length === 1 ? positive(args[0]) : null;
      return min === null
        ? fail(directive, '"words" needs the least number of words, for example "words 50".')
        : ok({ type: 'words', min });
    }
    case 'code-block':
      return args.length > 1
        ? fail(directive, '"code-block" takes one language name at most.')
        : ok({ type: 'codeBlock', language: args[0] ?? null });
    case 'code-language': return none({ type: 'codeLanguage' });
    case 'nested-list': return none({ type: 'nestedList' });
    case 'quote': return none({ type: 'quote' });
    case 'reference-link': return none({ type: 'referenceLink' });
    case 'image-alt': return none({ type: 'imageAlt' });
    case 'emphasis': return none({ type: 'emphasis' });
    case 'strong': return none({ type: 'strong' });
    default: return fail(directive, `Unknown check "${parts[0]}".`);
  }
}

/**
 * @param {Directive} directive
 * @returns {{ok: true, limit: SectionLimit} | {ok: false, note: DirectiveNote}}
 */
export function parseLimit(directive) {
  const parts = directive.value.split(/\s+/).filter(Boolean);
  const max = parts.length >= 2 ? positive(parts[parts.length - 1]) : null;
  if (max === null) return fail(directive, 'A limit needs a heading and a number, for example "limit: Introduction 200".');
  return { ok: true, limit: { heading: parts.slice(0, -1).join(' '), maxWords: max } };
}
