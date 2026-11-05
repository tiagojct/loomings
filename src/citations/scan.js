// ========================================
// Loomings — citation scanner
// Finds Pandoc citations in Markdown source: [@key], [@a; @b],
// [see @key, p. 3], [-@key] and bare @key. Code, HTML, link destinations,
// autolinks, plain URLs and the frontmatter are skipped. Offsets are UTF-16
// code units.
// Pure: no DOM, no Node or browser APIs (JavaScriptCore runs it too).
// ========================================

import MarkdownIt from 'markdown-it';
import { parseSource } from '../teaching/parse.js';

/**
 * @typedef {{key: string, prefix: string, suffix: string, locator: string|null,
 *   label: string|null, suppressAuthor: boolean}} CiteItem
 * @typedef {{from: number, to: number, bare: boolean, items: CiteItem[]}} Citation
 */

// A key starts with a letter, digit or underscore. Internal punctuation must
// have a key character after it, so no key ends in punctuation.
const KEY = '[\\p{L}\\p{N}_](?:[\\p{L}\\p{N}_]|[:.#$%&\\-+?<>~/](?=[\\p{L}\\p{N}_]))*';
// One pass: a bracket group, or a bare key. The code tests the character
// before a key, because the build target has no lookbehind in a RegExp.
const SCAN = new RegExp(`\\[([^\\[\\]]*)\\]|@(${KEY})`, 'gu');
const ITEM_KEY = new RegExp(`(-?)@(${KEY})`, 'gu');
const ENDS_IN_KEY_CHAR = /[\p{L}\p{N}_]$/u;

/**
 * True when a letter, digit or underscore comes right before `index`. Two code
 * units hold a whole character.
 *
 * @param {string} text
 * @param {number} index
 */
const keyCharBefore = (text, index) => ENDS_IN_KEY_CHAR.test(text.slice(Math.max(0, index - 2), index));

/**
 * The first key of an item that has no key character before it.
 *
 * @param {string} part
 * @returns {RegExpExecArray|null}
 */
function findItemKey(part) {
  ITEM_KEY.lastIndex = 0;
  let m;
  while ((m = ITEM_KEY.exec(part)) !== null) {
    if (!keyCharBefore(part, m.index)) return m;
    ITEM_KEY.lastIndex = m.index + 1;
  }
  return null;
}

/**
 * True when an odd number of backslashes come right before `index`.
 *
 * @param {string} text
 * @param {number} index
 */
function escaped(text, index) {
  let n = 0;
  while (index - n > 0 && text[index - n - 1] === '\\') n++;
  return n % 2 === 1;
}

const DEFINITION = /^ {0,3}\[[^\]]*\]:/;

// The preview links plain URLs and parseSource does not, so a key inside a URL
// is found here. This is the same linkify-it setup as the preview.
const LINKIFY = new MarkdownIt().linkify;

/**
 * Makes a test for "this offset is inside a plain URL". Each line is matched
 * once, and only when a key is on it.
 *
 * @param {string} source
 * @returns {(offset: number) => boolean}
 */
function urlTest(source) {
  let from = 0;
  let to = -1;
  /** @type {{index: number, lastIndex: number}[]} */
  let links = [];
  return (offset) => {
    if (offset < from || offset >= to) {
      from = source.lastIndexOf('\n', offset) + 1;
      const end = source.indexOf('\n', offset);
      to = end < 0 ? source.length : end;
      links = LINKIFY.match(source.slice(from, to)) ?? [];
    }
    // The links are in text order, so a binary search finds the one at this offset.
    const at = offset - from;
    let low = 0;
    let high = links.length;
    while (low < high) {
      const mid = (low + high) >> 1;
      if (links[mid].lastIndex <= at) low = mid + 1;
      else high = mid;
    }
    return low < links.length && at >= links[low].index;
  };
}

const LABELS = /** @type {Record<string, string>} */ ({
  'p.': 'page', 'pp.': 'page', 'chap.': 'chapter', 'sec.': 'section', 'vol.': 'volume', 'fig.': 'figure',
});
const LOCATOR_LABEL = /^(?:pp?\.|chap\.|sec\.|vol\.|fig\.)/;

/**
 * One space for each run of white space, as Pandoc does. Citeproc needs time
 * for the square of a run, and a share link can hold a million spaces.
 *
 * @param {string} text
 */
const oneSpace = (text) => text.replace(/\s+/g, ' ');

/**
 * Reads the text after a key.
 *
 * @param {string} rest
 * @returns {{locator: string|null, label: string|null, suffix: string}}
 */
function readSuffix(rest) {
  const start = rest.trimStart();
  if (!start.startsWith(',')) return { locator: null, label: null, suffix: oneSpace(start.trimEnd()) };
  const after = oneSpace(start.slice(1).trim());
  const label = LOCATOR_LABEL.exec(after)?.[0];
  if (!label && !/^\d/.test(after)) return { locator: null, label: null, suffix: after };
  // A cut at the first comma, not a RegExp: spaces in a share link must not take seconds.
  const body = label ? after.slice(label.length) : after;
  const comma = body.indexOf(',');
  return {
    locator: (comma < 0 ? body : body.slice(0, comma)).trim(),
    label: label ? LABELS[label] : 'page',
    suffix: comma < 0 ? '' : body.slice(comma + 1).trim(),
  };
}

/**
 * @param {string} inner  the text between the brackets
 * @param {number} offset  the offset of `inner` in the source
 * @param {(offset: number) => boolean} inUrl
 * @returns {CiteItem[]}
 */
function readItems(inner, offset, inUrl) {
  /** @type {CiteItem[]} */
  const items = [];
  let at = offset;
  for (const part of inner.split(';')) {
    const start = at;
    at += part.length + 1;
    const m = findItemKey(part);
    if (!m || escaped(part, m.index + m[1].length)) continue;
    if (inUrl(start + m.index + m[1].length)) continue;
    const prefix = oneSpace(part.slice(0, m.index));
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
  // Link reference definitions give no token, so find them by line.
  for (const line of doc.lines) {
    if (DEFINITION.test(line.text)) ranges.push({ from: line.from, to: line.end });
  }
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
  const inUrl = urlTest(source);
  /** @type {Citation[]} */
  const found = [];
  let k = 0;
  SCAN.lastIndex = 0;
  let m;
  while ((m = SCAN.exec(source)) !== null) {
    const start = m.index;
    if (m[2] !== undefined && keyCharBefore(source, start)) {
      SCAN.lastIndex = start + 1;
      continue;
    }
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
      if (escaped(source, start) || inUrl(start)) continue;
      found.push({
        from: start, to: end, bare: true,
        items: [{ key: m[2], prefix: '', suffix: '', locator: null, label: null, suppressAuthor: false }],
      });
      continue;
    }
    if (escaped(source, start)) { SCAN.lastIndex = end; continue; }
    const items = readItems(m[1], start + 1, inUrl);
    const next = source[end];
    if (!items.length) { SCAN.lastIndex = start + 1; continue; }
    if (next === '(' || next === '[' || next === '{') { SCAN.lastIndex = end; continue; }
    found.push({ from: start, to: end, bare: false, items });
  }
  return found;
}
