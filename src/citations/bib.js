// ========================================
// Loomings — bibliography parser
// Reads BibTeX or BibLaTeX text into CSL-JSON items. The whole file is parsed
// first. If that fails, each entry is parsed alone, so one bad entry does not
// remove the others. Notes tell the writer what was skipped.
// Pure: no DOM, no Node or browser APIs (a worker and JavaScriptCore run it).
// The function takes a string. Decoding of bytes is done by the caller.
// ========================================

import { Cite } from '@citation-js/core';
import '@citation-js/plugin-bibtex';

/**
 * @typedef {Record<string, any> & {id: string}} CslItem
 * @typedef {{line: number, key?: string, message: string}} BibNote
 * @typedef {{kind: string, key: string|undefined, line: number, text: string, closed: boolean}} Block
 */

const START = /@([A-Za-z]+)[ \t]*([{(])/g;
const LINE_START = /^[ \t]*@[A-Za-z]+[ \t]*[{(]/;
const KEY = /^[\s]*([^\s,{}()=]+)[ \t\r\n]*,/;
const NO_ITEM = new Set(['string', 'comment', 'preamble']);

/**
 * Splits the text into top-level @ blocks with a brace counter. A block that
 * is not closed ends before the next line that starts an entry.
 *
 * @param {string} text
 * @returns {Block[]}
 */
function scanBlocks(text) {
  /** @type {Block[]} */
  const blocks = [];
  // Line number of each offset is found by counting newlines up to it.
  let line = 0;
  let linePos = 0;
  /** @param {number} offset */
  const lineAt = (offset) => {
    for (let i = linePos; i < offset; i++) if (text.charCodeAt(i) === 10) line++;
    linePos = Math.max(linePos, offset);
    return line;
  };
  let pos = 0;
  while (pos < text.length) {
    START.lastIndex = pos;
    const m = START.exec(text);
    if (!m) break;
    const open = m[2];
    const close = open === '{' ? '}' : ')';
    const bodyStart = m.index + m[0].length;
    let depth = 1;
    let i = bodyStart;
    let closed = false;
    for (; i < text.length; i++) {
      const c = text[i];
      if (c === open) depth++;
      else if (c === close) {
        depth--;
        if (depth === 0) { closed = true; i++; break; }
      } else if (c === '\n') {
        // An unclosed block stops where the next entry begins.
        const rest = text.slice(i + 1, i + 80);
        if (LINE_START.test(rest) && /^@/.test(rest)) break;
      }
    }
    const kind = m[1].toLowerCase();
    const body = text.slice(bodyStart, i);
    const keyMatch = NO_ITEM.has(kind) ? null : KEY.exec(body);
    blocks.push({
      kind,
      key: keyMatch ? keyMatch[1] : undefined,
      line: lineAt(m.index),
      text: text.slice(m.index, i),
      closed,
    });
    pos = Math.max(i, m.index + 1);
  }
  return blocks;
}

/**
 * @param {string} text
 * @returns {CslItem[]}
 */
function parseText(text) {
  const data = new Cite(text, { forceType: '@biblatex/text' }).data;
  return /** @type {CslItem[]} */ (data);
}

/**
 * Parses a bibliography.
 *
 * @param {string} text
 * @returns {{items: CslItem[], notes: BibNote[]}}
 */
export function parseBibliography(text) {
  /** @type {CslItem[]} */
  const items = [];
  /** @type {BibNote[]} */
  const notes = [];
  if (typeof text !== 'string') return { items, notes };
  const source = text.replace(/^﻿/, '');
  if (!/@/.test(source)) return { items, notes };

  /** @type {Block[]|null} */
  let blocks = null;
  const getBlocks = () => (blocks ??= scanBlocks(source));

  /** @type {Map<string, number>} */
  const seen = new Map();
  /**
   * Adds an item. The first item with a key wins.
   *
   * @param {CslItem} item
   * @param {number} [line] the line of the block, if known
   */
  const add = (item, line) => {
    const count = seen.get(item.id);
    if (count === undefined) {
      seen.set(item.id, 1);
      items.push(item);
      return;
    }
    seen.set(item.id, count + 1);
    let at = line;
    if (at === undefined) {
      // The (count + 1)th block with this key is the later entry.
      const same = getBlocks().filter((b) => b.key === item.id);
      at = same[count]?.line ?? same[same.length - 1]?.line ?? 0;
    }
    notes.push({
      line: at,
      key: item.id,
      message: `Entry ${item.id} is a duplicate. The first entry is used.`,
    });
  };

  try {
    for (const item of parseText(source)) add(item);
    return { items, notes };
  } catch {
    // One entry has an error. Read the entries one at a time.
    items.length = 0;
    notes.length = 0;
    seen.clear();
  }

  const all = getBlocks();
  const strings = all.filter((b) => b.kind === 'string' && b.closed).map((b) => b.text).join('\n');
  for (const block of all) {
    if (NO_ITEM.has(block.kind)) continue;
    const name = block.key ? `Entry ${block.key}` : `The entry on line ${block.line + 1}`;
    if (!block.closed) {
      notes.push({ line: block.line, key: block.key, message: `${name} could not be read: a brace is not closed.` });
      continue;
    }
    try {
      const parsed = parseText(`${strings}\n${block.text}`);
      for (const item of parsed) add(item, block.line);
    } catch {
      notes.push({ line: block.line, key: block.key, message: `${name} could not be read: the syntax is not correct.` });
    }
  }
  return { items, notes };
}
