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
const NEXT_ENTRY = /\n(?=@[A-Za-z]+[ \t]*[{(])/g;
const KEY = /^[\s]*([^\s,{}()=]+)[ \t\r\n]*,/;
const NO_ITEM = new Set(['string', 'comment', 'preamble']);
// A file with a bad pattern can give one note for each entry.
const MAX_NOTES = 50;

/**
 * For each opening `{` and `(`, the offset after its closing mark. Each kind
 * has its own count, and 0 means not closed. One pass, so a text with many
 * unclosed blocks does not cost one pass for each block.
 *
 * @param {string} text
 * @returns {Int32Array}
 */
function matchClosers(text) {
  const closers = new Int32Array(text.length);
  /** @type {number[]} */
  const braces = [];
  /** @type {number[]} */
  const parens = [];
  for (let i = 0; i < text.length; i++) {
    const c = text.charCodeAt(i);
    if (c === 123) braces.push(i);
    else if (c === 40) parens.push(i);
    else if (c === 125 || c === 41) {
      const opener = (c === 125 ? braces : parens).pop();
      if (opener !== undefined) closers[opener] = i + 1;
    }
  }
  return closers;
}

/**
 * Keeps the first notes, and one note that counts the others.
 *
 * @param {BibNote[]} notes
 * @returns {BibNote[]}
 */
function capNotes(notes) {
  if (notes.length <= MAX_NOTES + 1) return notes;
  const more = notes.length - MAX_NOTES;
  return [...notes.slice(0, MAX_NOTES), { line: notes[MAX_NOTES].line, message: `${more} more notes for this file are not shown.` }];
}

/**
 * Splits the text into top-level @ blocks. A block that is not closed ends
 * before the next line that starts an entry.
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
  const closers = matchClosers(text);
  let pos = 0;
  while (pos < text.length) {
    START.lastIndex = pos;
    const m = START.exec(text);
    if (!m) break;
    const bodyStart = m.index + m[0].length;
    let i = closers[bodyStart - 1];
    const closed = i > 0;
    if (!closed) {
      // An unclosed block ends before the next line that starts an entry.
      NEXT_ENTRY.lastIndex = bodyStart;
      const next = NEXT_ENTRY.exec(text);
      i = next ? next.index + 1 : text.length;
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
  /** @type {Map<string|undefined, Block[]>|null} */
  let byKey = null;
  /** @param {string} key  The blocks with this key. One pass, for each duplicate. */
  const blocksOf = (key) => {
    if (!byKey) {
      byKey = new Map();
      for (const block of getBlocks()) {
        const same = byKey.get(block.key);
        if (same) same.push(block);
        else byKey.set(block.key, [block]);
      }
    }
    return byKey.get(key) ?? [];
  };
  /**
   * Adds an item. The first item with a key wins.
   *
   * @param {CslItem} rawItem
   * @param {number} [line] the line of the block, if known
   */
  const add = (rawItem, line) => {
    // citation-js adds the whole source text as _graph. Drop it and the key copy.
    const { _graph, 'citation-key': _key, ...item } = rawItem;
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
      const same = blocksOf(item.id);
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
    return { items, notes: capNotes(notes) };
  } catch {
    // One entry has an error. Read the entries one at a time.
    items.length = 0;
    notes.length = 0;
    seen.clear();
  }

  const all = getBlocks();
  const goodStrings = [];
  for (const block of all) {
    if (block.kind !== 'string' || !block.closed) continue;
    try {
      parseText(`${block.text}\n@misc{x, title = {x}}`);
      goodStrings.push(block.text);
    } catch {
      notes.push({ line: block.line, message: 'A string definition could not be read. It is not used.' });
    }
  }
  const strings = goodStrings.join('\n');
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
  return { items, notes: capNotes(notes) };
}
