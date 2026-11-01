// ========================================
// Loomings — the teaching parse
// One markdown-it parse of a document for the checker and the exercise
// checks, with what they need to point back into the source: the original
// lines (any line ending), the frontmatter (never checked), and source
// offsets for inline marks, images, code spans and links. Pure: no DOM.
//
// markdown-it keeps no inline positions, so every inline rule is wrapped to
// stamp the tokens it pushes with their offsets in the inline content, and
// `sourceOffset` maps those back to UTF-16 offsets in the document.
// ========================================

import MarkdownIt from 'markdown-it';

/**
 * @typedef {{from: number, text: string, end: number}} SourceLine
 *   from: offset of the line start; text: the line without its terminator;
 *   end: offset just past the terminator.
 * @typedef {{from: number, to: number}} Range
 */

/**
 * The frontmatter's lines, matching the native app: a first line of exactly
 * `---` and a closing line of exactly `---` by line 50.
 *
 * @param {SourceLine[]} lines
 * @returns {{first: number, last: number}|null} 0-based line indices
 */
export function frontmatterLines(lines) {
  if (!lines.length || lines[0].text !== '---') return null;
  for (let i = 1; i < lines.length && i < 50; i++) {
    if (lines[i].text === '---') return { first: 0, last: i };
  }
  return null;
}

/**
 * The document's lines, split on CRLF, LF or CR.
 *
 * @param {string} source
 * @returns {SourceLine[]}
 */
export function splitLines(source) {
  /** @type {SourceLine[]} */
  const lines = [];
  const re = /\r\n|\n|\r/g;
  let from = 0;
  let m;
  while ((m = re.exec(source)) !== null) {
    lines.push({ from, text: source.slice(from, m.index), end: m.index + m[0].length });
    from = m.index + m[0].length;
  }
  if (from < source.length || lines.length === 0) {
    lines.push({ from, text: source.slice(from), end: source.length });
  }
  return lines;
}

const md = new MarkdownIt({ html: true, linkify: false, typographer: false });

/**
 * A fence's info string as cmark gives it: escapes and entities undone,
 * outer white space removed.
 *
 * @param {string} info
 * @returns {string}
 */
export function fenceInfo(info) {
  return md.utils.unescapeAll(info).trim();
}
// Escapes stay separate tokens (text_special) and leftover emphasis marks
// stay one token per mark, each with its own offset.
md.core.ruler.disable('text_join');
md.inline.ruler2.disable('fragments_join');

const STAMPED_RUNS = new Set(['emphasis', 'strikethrough']);

for (const rule of /** @type {{name: string, fn: Function}[]} */ (/** @type {any} */ (md.inline.ruler).__rules__)) {
  const fn = rule.fn;
  const name = rule.name;
  md.inline.ruler.at(name, (state, silent) => {
    const start = state.pos;
    const count = state.tokens.length;
    const pending = state.pending.length;
    const ok = fn(state, silent);
    if (!ok || silent) return ok;
    let i = count;
    // Text gathered before this rule is flushed as the first new token.
    if (pending && i < state.tokens.length && state.tokens[i].type === 'text' && !state.tokens[i].meta) {
      state.tokens[i].meta = { pos: start - pending, end: start };
      i++;
    }
    for (let k = 0; i < state.tokens.length; i++, k++) {
      const token = state.tokens[i];
      if (token.meta && token.meta.pos !== undefined) continue;
      if (STAMPED_RUNS.has(name)) {
        token.meta = { ...(token.meta || {}), pos: start + k, end: start + k + 1, delim: name === 'emphasis' };
      } else if (k === 0) {
        token.meta = { ...(token.meta || {}), pos: start, end: state.pos };
      }
    }
    return ok;
  });
}

/**
 * Parses `source` once for the teaching features.
 *
 * @param {string} source
 */
export function parseSource(source) {
  const lines = splitLines(source);
  const frontmatter = frontmatterLines(lines);
  // markdown-it sees the same lines, LF-joined, with the frontmatter blank;
  // line indices stay the source's own.
  const texts = lines.map((l, i) => (frontmatter && i <= frontmatter.last ? '' : l.text));
  const env = {};
  const tokens = md.parse(texts.join('\n'), env);
  const lineEnding = source.includes('\r\n') ? '\r\n' : '\n';
  let contentEnd = source.length;
  while (contentEnd > 0 && /\s/.test(source[contentEnd - 1])) contentEnd--;
  return {
    source,
    lines,
    tokens,
    env,
    lineEnding,
    contentEnd,
    /** @type {Range|null} */
    frontmatter: frontmatter ? { from: 0, to: lines[frontmatter.last].from + lines[frontmatter.last].text.length } : null,
    mapper: createMapper(lines),
  };
}

/**
 * Finds `part` in `text` from `from`, letting a backslash-escaped pipe in the
 * text stand for a pipe in `part`. Returns the text offset of every character
 * of `part`, and one past its end, or null.
 *
 * @param {string} text
 * @param {string} part
 * @param {number} from
 * @returns {{offsets: number[]}|null}
 */
function findLoosely(text, part, from) {
  for (let s = from; s <= text.length - part.length; s++) {
    const offsets = [];
    let i = s;
    let j = 0;
    while (j < part.length && i < text.length) {
      if (text[i] === part[j]) { offsets.push(i); i++; j++; }
      else if (part[j] === '|' && text[i] === '\\' && text[i + 1] === '|') { offsets.push(i); i += 2; j++; }
      else break;
    }
    if (j === part.length) { offsets.push(i); return { offsets }; }
  }
  return null;
}

/**
 * Maps offsets in an inline token's content back to the document. A content
 * line is the end of its source line (containers and indentation removed),
 * except in table cells and ATX headings, which are found left to right.
 *
 * @param {SourceLine[]} lines
 */
function createMapper(lines) {
  /** @type {Map<number, number>} */
  const cursors = new Map();
  return {
    /**
     * @param {import('markdown-it/lib/token.mjs').default} inline
     * @param {boolean} ordered table cell or ATX heading content
     * @param {number} [row] the line of a table cell, whose token has no map
     * @returns {(offset: number) => number}
     */
    forInline(inline, ordered, row = 0) {
      const parts = inline.content.split('\n');
      const first = inline.map ? inline.map[0] : row;
      /** @type {{start: number, at: (d: number) => number}[]} */
      const starts = [];
      let start = 0;
      parts.forEach((part, k) => {
        const line = lines[first + k] || { from: 0, text: '', end: 0 };
        const text = line.text;
        const cursor = cursors.get(first + k) || 0;
        const end = line.from + text.length;
        /** @type {((d: number) => number)|null} */
        let at = null;
        if (ordered) {
          // A table cell or ATX heading: found left to right. markdown-it
          // drops the backslash of an escaped pipe, so \| may stand for |.
          const found = findLoosely(text, part, cursor);
          if (found) {
            at = (d) => line.from + found.offsets[Math.min(d, found.offsets.length - 1)];
            cursors.set(first + k, found.offsets[found.offsets.length - 1]);
          }
        } else {
          const trimmed = text.trimEnd();
          // markdown-it turns a tab it only partly consumes into spaces, so
          // a content line may begin with spaces the source does not have.
          const rest = part.replace(/^ +/, '');
          const lead = part.length - rest.length;
          let col = -1;
          let skip = 0;
          if (text.endsWith(part)) col = text.length - part.length;
          else if (trimmed.endsWith(part)) col = trimmed.length - part.length;
          else if (lead && text.endsWith(rest)) { col = text.length - rest.length; skip = lead; }
          else if (lead && trimmed.endsWith(rest)) { col = trimmed.length - rest.length; skip = lead; }
          else col = text.indexOf(part, cursor);
          if (col >= 0) {
            const base = line.from + col;
            at = (d) => base + Math.max(0, d - skip);
            cursors.set(first + k, col + part.length - skip);
          }
        }
        if (!at) {
          const base = line.from + Math.max(0, text.length - part.length);
          at = (d) => base + d;
          cursors.set(first + k, text.length);
        }
        const map = at;
        starts.push({ start, at: (d) => Math.min(end, map(d)) });
        start += part.length + 1;
      });
      return (offset) => {
        let k = starts.length - 1;
        while (k > 0 && starts[k].start > offset) k--;
        return starts[k].at(offset - starts[k].start);
      };
    },
  };
}
