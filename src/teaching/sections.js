// ========================================
// Loomings — section word limits
// `limit: <heading title> <max>` in the frontmatter sets a word limit for a
// section; each section counts its words, its own heading not counted, as
// the native app does (macos/Sources/LoomingsTeaching/SectionStatistics.swift).
// Pure: no DOM.
// ========================================

import { parseSource, splitLines } from './parse.js';
import { readDirectives, parseLimit } from './directives.js';
import { countWords } from '../stats.js';

/**
 * @typedef {{level: number, title: string, from: number}} Heading  from: line start
 * @typedef {{heading: Heading, from: number, to: number, words: number, limit: number|null}} SectionCount
 * @typedef {import('./directives.js').SectionLimit} SectionLimit
 */

/**
 * The headings, with titles taken from the source as the native outline
 * does: the text after the # signs without a closing run, or the first line
 * of a setext heading.
 *
 * @param {string} source
 * @returns {Heading[]}
 */
export function outline(source) {
  const doc = parseSource(source);
  /** @type {Heading[]} */
  const headings = [];
  for (const token of doc.tokens) {
    if (token.type !== 'heading_open' || !token.map) continue;
    const line = doc.lines[token.map[0]];
    const text = line.text;
    let title;
    if (text[0] === '#') {
      let cursor = 0;
      while (text[cursor] === '#') cursor++;
      let end = text.length;
      while (end > cursor && (text[end - 1] === ' ' || text[end - 1] === '\t')) end--;
      let closing = end;
      while (closing > cursor && text[closing - 1] === '#') closing--;
      title = text.slice(cursor, closing).trim();
    } else {
      title = text.trim();
    }
    headings.push({ level: Number(token.tag.slice(1)), title, from: line.from });
  }
  return headings;
}

/**
 * The limit: directives, and notes for any that cannot be read.
 *
 * @param {string} source
 * @returns {{limits: SectionLimit[], notes: import('./directives.js').DirectiveNote[]}}
 */
export function limitsIn(source) {
  /** @type {SectionLimit[]} */ const limits = [];
  /** @type {import('./directives.js').DirectiveNote[]} */ const notes = [];
  for (const directive of readDirectives(source)) {
    if (directive.key !== 'limit') continue;
    const parsed = parseLimit(directive);
    if (parsed.ok) limits.push(parsed.limit); else notes.push(parsed.note);
  }
  return { limits, notes };
}

const normalized = (/** @type {string} */ title) => title.trim().toLowerCase();

/**
 * Every section, or with onlyLimited only those a limit names.
 *
 * @param {string} source
 * @param {Heading[]} headings
 * @param {SectionLimit[]} limits
 * @param {{onlyLimited?: boolean}} [options]
 * @returns {SectionCount[]}
 */
export function sections(source, headings, limits, { onlyLimited = false } = {}) {
  /** @type {Map<string, number>} */
  const wanted = new Map();
  for (const limit of limits) {
    const key = normalized(limit.heading);
    if (!wanted.has(key)) wanted.set(key, limit.maxWords);
  }
  const lines = splitLines(source);
  /** @type {SectionCount[]} */
  const out = [];
  headings.forEach((heading, index) => {
    const limit = wanted.get(normalized(heading.title)) ?? null;
    if (onlyLimited && limit === null) return;
    const from = Math.min(heading.from, source.length);
    const next = headings.slice(index + 1).find((h) => h.level <= heading.level);
    const to = Math.min(next ? next.from : source.length, source.length);
    const bodyFrom = Math.min(to, endOfHeading(from));
    out.push({ heading, from, to: Math.max(from, to), words: countWords(source.slice(bodyFrom, Math.max(bodyFrom, to))), limit });
  });
  return out;

  /** Just past the heading's line, and past a setext underline. */
  function endOfHeading(at) {
    let n = 0;
    while (n + 1 < lines.length && lines[n + 1].from <= at) n++;
    const end = lines[n].end;
    if (end >= source.length || n + 1 >= lines.length) return end;
    const underline = lines[n + 1].text.trim();
    if (!lines[n].text.replace(/^[ \t]+/, '').startsWith('#') && underline
      && (/^=+$/.test(underline) || /^-+$/.test(underline))) {
      return lines[n + 1].end;
    }
    return end;
  }
}

/**
 * The innermost limited section around `caret` (its end included), or null.
 *
 * @param {SectionCount[]} list
 * @param {number} caret
 * @returns {SectionCount|null}
 */
export function sectionAt(list, caret) {
  /** @type {SectionCount|null} */
  let best = null;
  for (const section of list) {
    if (section.limit === null) continue;
    if (!((caret >= section.from && caret < section.to) || caret === section.to)) continue;
    if (!best || section.heading.level > best.heading.level) best = section;
  }
  return best;
}
