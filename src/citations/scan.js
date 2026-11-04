// ========================================
// Loomings — citation scanner
// Finds Pandoc citations in Markdown source: [@key], [@a; @b],
// [see @key, p. 3], [-@key] and bare @key. Code, HTML, link destinations,
// autolinks and the frontmatter are skipped. Offsets are UTF-16 code units.
// Pure: no DOM, no Node or browser APIs (JavaScriptCore runs it too).
// ========================================

import { parseSource } from '../teaching/parse.js';

/**
 * @typedef {{key: string, prefix: string, suffix: string, locator: string|null,
 *   label: string|null, suppressAuthor: boolean}} CiteItem
 * @typedef {{from: number, to: number, bare: boolean, items: CiteItem[]}} Citation
 */

// A key starts with a letter, digit or underscore. Internal punctuation must
// have a key character after it, so no key ends in punctuation.
const KEY = '[\\p{L}\\p{N}_](?:[\\p{L}\\p{N}_]|[:.#$%&\\-+?<>~/](?=[\\p{L}\\p{N}_]))*';
// One pass: a bracket group, or a bare key that has no letter, digit or
// backslash before it.
const SCAN = new RegExp(`\\[([^\\[\\]]*)\\]|(?<![\\p{L}\\p{N}_\\\\])@(${KEY})`, 'gu');
const ITEM_KEY = new RegExp(`(?<![\\p{L}\\p{N}_\\\\])(-?)@(${KEY})`, 'u');

const LABELS = /** @type {Record<string, string>} */ ({
  'p.': 'page', 'pp.': 'page', 'chap.': 'chapter', 'sec.': 'section', 'vol.': 'volume', 'fig.': 'figure',
});
const LOCATOR = /^(pp?\.|chap\.|sec\.|vol\.|fig\.)[ \t]*([^,]*?)[ \t]*(?:,[ \t]*(.*))?$/s;
const PLAIN_LOCATOR = /^(\d[^,]*?)[ \t]*(?:,[ \t]*(.*))?$/s;

/**
 * Reads the text after a key.
 *
 * @param {string} rest
 * @returns {{locator: string|null, label: string|null, suffix: string}}
 */
function readSuffix(rest) {
  const trimmed = rest.trim();
  if (!rest.trimStart().startsWith(',')) return { locator: null, label: null, suffix: trimmed };
  const after = rest.trimStart().slice(1).trim();
  const m = LOCATOR.exec(after);
  if (m) return { locator: m[2], label: LABELS[m[1]], suffix: (m[3] || '').trim() };
  const p = PLAIN_LOCATOR.exec(after);
  if (p) return { locator: p[1], label: 'page', suffix: (p[2] || '').trim() };
  return { locator: null, label: null, suffix: after };
}

/**
 * @param {string} inner  the text between the brackets
 * @returns {CiteItem[]}
 */
function readItems(inner) {
  /** @type {CiteItem[]} */
  const items = [];
  for (const part of inner.split(';')) {
    const m = ITEM_KEY.exec(part);
    if (!m) continue;
    const prefix = part.slice(0, m.index);
    items.push({
      key: m[2],
      prefix: prefix.trim() ? prefix : '',
      ...readSuffix(part.slice(m.index + m[0].length)),
      suppressAuthor: m[1] === '-',
    });
  }
  return items;
}

/**
 * Ranges where nothing is a citation: the frontmatter, code, HTML, autolinks
 * and link or image destinations. Sorted by start.
 *
 * @param {string} source
 * @returns {{from: number, to: number}[]}
 */
function skipRanges(source) {
  const doc = parseSource(source);
  /** @type {{from: number, to: number}[]} */
  const ranges = [];
  if (doc.frontmatter) ranges.push({ from: 0, to: doc.frontmatter.to });
  const lineEnd = (/** @type {number} */ i) => (doc.lines[i] ? doc.lines[i].end : source.length);
  const lineFrom = (/** @type {number} */ i) => (doc.lines[i] ? doc.lines[i].from : source.length);
  for (const tok of doc.tokens) {
    if ((tok.type === 'fence' || tok.type === 'code_block' || tok.type === 'html_block') && tok.map) {
      ranges.push({ from: lineFrom(tok.map[0]), to: lineEnd(tok.map[1] - 1) });
    } else if (tok.type === 'inline' && tok.children && tok.children.length && tok.map) {
      const at = doc.mapper.forInline(tok, false);
      for (const child of tok.children) {
        const meta = child.meta;
        if (!meta || meta.pos === undefined) continue;
        const from = at(meta.pos);
        const to = at(meta.end);
        if (child.type === 'code_inline' || child.type === 'html_inline') {
          ranges.push({ from, to });
        } else if (child.type === 'link_open' && child.markup === 'autolink') {
          ranges.push({ from, to });
        } else if (child.type === 'link_open' || child.type === 'image') {
          // The destination and title start at the last `](`.
          const cut = source.slice(from, to).lastIndexOf('](');
          if (cut >= 0) ranges.push({ from: from + cut + 1, to });
        }
      }
    }
  }
  ranges.sort((a, b) => a.from - b.from);
  return ranges;
}

/**
 * Finds the citations in a Markdown source.
 *
 * @param {string} source
 * @returns {Citation[]}
 */
export function scanCitations(source) {
  if (!source.includes('@')) return [];
  const skips = skipRanges(source);
  /** @type {Citation[]} */
  const found = [];
  let k = 0;
  SCAN.lastIndex = 0;
  let m;
  while ((m = SCAN.exec(source)) !== null) {
    const start = m.index;
    const end = start + m[0].length;
    while (k < skips.length && skips[k].to <= start) k++;
    // Skip ranges can nest or overlap, so test the ones that start before us.
    let skipTo = -1;
    for (let j = k; j < skips.length && skips[j].from <= start; j++) {
      if (skips[j].to > start && skips[j].to > skipTo) skipTo = skips[j].to;
    }
    if (skipTo >= 0) {
      SCAN.lastIndex = Math.max(skipTo, start + 1);
      continue;
    }
    if (m[2] !== undefined) {
      found.push({
        from: start, to: end, bare: true,
        items: [{ key: m[2], prefix: '', suffix: '', locator: null, label: null, suppressAuthor: false }],
      });
      continue;
    }
    if (start > 0 && source[start - 1] === '\\') { SCAN.lastIndex = start + 1; continue; }
    const items = readItems(m[1]);
    const next = source[end];
    if (!items.length) { SCAN.lastIndex = start + 1; continue; }
    if (next === '(' || next === '[' || next === '{') { SCAN.lastIndex = end; continue; }
    found.push({ from: start, to: end, bare: false, items });
  }
  return found;
}
