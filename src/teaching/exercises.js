// ========================================
// Loomings — exercises that check themselves
// Evaluates a document's `check:` directives, and the checks a bundled
// lesson brings with it (lessons/checks.json), as the native app does
// (macos/Sources/LoomingsTeaching/ExerciseEvaluator.swift); both pass
// macos/Tests/LoomingsTeachingTests/Fixtures/check-cases.json. Pure: no DOM.
// ========================================

import { parseSource } from './parse.js';
import { readDirectives, parseCheck } from './directives.js';
import { countWords } from '../stats.js';

/**
 * @typedef {import('./directives.js').Check} Check
 * @typedef {import('./directives.js').DirectiveNote} DirectiveNote
 * @typedef {{check: Check, label: string, passed: boolean, detail: string}} CheckResult
 * @typedef {{checks: Check[], after: string|null}} AttachedChecks
 */

/**
 * @param {string} source
 * @param {AttachedChecks|null} [attached]
 * @returns {{results: CheckResult[], notes: DirectiveNote[]}}
 */
export function evaluate(source, attached = null) {
  /** @type {Check[]} */
  const checks = [];
  /** @type {DirectiveNote[]} */
  const notes = [];
  for (const directive of readDirectives(source)) {
    if (directive.key !== 'check') continue;
    const parsed = parseCheck(directive);
    if (parsed.ok) checks.push(parsed.check); else notes.push(parsed.note);
  }
  /** @type {CheckResult[]} */
  const results = [];
  if (checks.length) {
    const found = census(source);
    results.push(...checks.map((c) => result(found, c)));
  }
  if (attached && attached.checks.length) {
    const found = census(scope(source, attached.after));
    results.push(...attached.checks.map((c) => result(found, c)));
  }
  return { results, notes };
}

const isLowSurrogate = (/** @type {number} */ unit) => unit >= 0xdc00 && unit <= 0xdfff;

/**
 * The part of `source` after the anchor (the lesson's original text):
 * everything after it while the document still starts with it, else after
 * its last line, else after the point where the document stops matching it.
 *
 * @param {string} source
 * @param {string|null} anchor
 * @returns {string}
 */
export function scope(source, anchor) {
  if (anchor === null || anchor === undefined) return source;
  const trimmed = anchor.trim();
  if (!trimmed) return source;
  if (source.startsWith(trimmed)) return source.slice(trimmed.length);
  const lastLine = trimmed.split('\n').filter(Boolean).pop() ?? trimmed;
  const found = source.lastIndexOf(lastLine);
  if (found >= 0) return source.slice(found + lastLine.length);
  let common = 0;
  while (common < source.length && common < trimmed.length && source.charCodeAt(common) === trimmed.charCodeAt(common)) common++;
  while (common > 0 && common < source.length && isLowSurrogate(source.charCodeAt(common))) common--;
  return source.slice(common);
}

/**
 * What a document contains, counted once.
 *
 * @param {string} source
 */
function census(source) {
  const doc = parseSource(source);
  const found = {
    /** @type {number[]} */ headings: [],
    /** @type {number[]} */ bulletLists: [],
    /** @type {number[]} */ orderedLists: [],
    nested: false,
    quotes: 0,
    /** @type {(string|null)[]} */ codeLanguages: [],
    inlineCode: 0,
    links: 0,
    referenceLinks: 0,
    imagesWithAlt: 0,
    /** @type {number[]} */ tableRows: [],
    emphasis: 0,
    strong: 0,
    words: countWords(doc.frontmatter ? source.slice(doc.frontmatter.to) : source),
  };
  /** @type {{ordered: boolean, items: number}[]} */
  const lists = [];
  let items = 0;
  let inBody = false;
  let rows = 0;
  for (const token of doc.tokens) {
    switch (token.type) {
      case 'heading_open': found.headings.push(Number(token.tag.slice(1))); break;
      case 'bullet_list_open':
      case 'ordered_list_open':
        if (items > 0) found.nested = true;
        lists.push({ ordered: token.type === 'ordered_list_open', items: 0 });
        break;
      case 'bullet_list_close':
      case 'ordered_list_close': {
        const list = lists.pop();
        if (list) (list.ordered ? found.orderedLists : found.bulletLists).push(list.items);
        break;
      }
      case 'list_item_open': items++; if (lists.length) lists[lists.length - 1].items++; break;
      case 'list_item_close': items--; break;
      case 'blockquote_open': found.quotes++; break;
      case 'fence': {
        // As the native app: a block counts as fenced only when its opening
        // line starts with the fence.
        const opening = token.map ? doc.lines[token.map[0]].text.trim() : '';
        const fenced = opening.startsWith('```') || opening.startsWith('~~~');
        const language = fenced ? token.info.split(' ')[0].toLowerCase() : '';
        found.codeLanguages.push(language || null);
        break;
      }
      case 'code_block': found.codeLanguages.push(null); break;
      case 'table_open': rows = 0; break;
      case 'tbody_open': inBody = true; break;
      case 'tbody_close': inBody = false; break;
      case 'tr_open': if (inBody) rows++; break;
      case 'table_close': found.tableRows.push(rows); break;
      case 'inline': if (token.children) inline(token.children, token.content); break;
    }
  }
  return found;

  /**
   * @param {import('markdown-it/lib/token.mjs').default[]} children
   * @param {string} src the inline content the children's offsets refer to
   */
  function inline(children, src) {
    for (const child of children) {
      switch (child.type) {
        case 'code_inline': found.inlineCode++; break;
        case 'em_open': found.emphasis++; break;
        case 'strong_open': found.strong++; break;
        case 'link_open':
          found.links++;
          if (child.meta?.end !== undefined && src[child.meta.end - 1] === ']') found.referenceLinks++;
          break;
        case 'image': {
          let alt = '';
          let level = 0;
          for (const part of child.children || []) {
            if (part.nesting === -1) level--;
            if (level === 0 && (part.type === 'text' || part.type === 'text_special')) alt += part.content;
            if (part.nesting === 1) level++;
          }
          if (alt.replace(/[ \t]/g, '')) found.imagesWithAlt++;
          if (child.children) inline(child.children, child.content);
          break;
        }
      }
    }
  }
}

/**
 * @param {ReturnType<typeof census>} found
 * @param {Check} check
 * @returns {CheckResult}
 */
function result(found, check) {
  const make = (/** @type {string} */ label, /** @type {boolean} */ passed, /** @type {string} */ detail) => ({ check, label, passed, detail });
  const plural = (/** @type {number} */ n, /** @type {string} */ one, /** @type {string} */ many) => `${n} ${n === 1 ? one : many}`;
  const max = (/** @type {number[]} */ list) => (list.length ? Math.max(...list) : 0);
  switch (check.type) {
    case 'heading': {
      const count = found.headings.filter((l) => check.level === null || l === check.level).length;
      const kind = check.level === null ? '' : `level-${check.level} `;
      const label = check.min === 1 ? `A ${kind}heading` : `${check.min} ${kind}headings`;
      return make(label, count >= check.min, `found ${count}`);
    }
    case 'bulletList': {
      const best = max(found.bulletLists);
      return make(`A bulleted list of ${plural(check.items, 'item', 'items')}`, best >= check.items,
        found.bulletLists.length ? `longest has ${plural(best, 'item', 'items')}` : 'no bulleted list yet');
    }
    case 'orderedList': {
      const best = max(found.orderedLists);
      return make(`A numbered list of ${plural(check.items, 'item', 'items')}`, best >= check.items,
        found.orderedLists.length ? `longest has ${plural(best, 'item', 'items')}` : 'no numbered list yet');
    }
    case 'nestedList':
      return make('A list inside a list', found.nested, found.nested ? 'found' : 'not yet');
    case 'quote':
      return make('A quotation', found.quotes > 0, found.quotes > 0 ? 'found' : 'not yet');
    case 'codeBlock': {
      const wanted = check.language?.toLowerCase();
      const ok = wanted ? found.codeLanguages.includes(wanted) : found.codeLanguages.length > 0;
      return make(check.language ? `A ${check.language} code block` : 'A code block', ok, ok ? 'found' : 'not yet');
    }
    case 'codeLanguage': {
      const ok = found.codeLanguages.some((l) => l !== null);
      return make('A code block with its language named', ok, ok ? 'found' : 'not yet');
    }
    case 'inlineCode':
      return make(check.min === 1 ? 'Inline code' : `${check.min} pieces of inline code`, found.inlineCode >= check.min, `found ${found.inlineCode}`);
    case 'link':
      return make(check.min === 1 ? 'A link' : `${check.min} links`, found.links >= check.min, `found ${found.links}`);
    case 'referenceLink':
      return make('A reference link', found.referenceLinks > 0, found.referenceLinks > 0 ? 'found' : 'not yet');
    case 'imageAlt':
      return make('An image with alternative text', found.imagesWithAlt > 0, found.imagesWithAlt > 0 ? 'found' : 'not yet');
    case 'table': {
      const best = max(found.tableRows);
      return make(`A table with ${plural(check.rows, 'row', 'rows')}`, best >= check.rows,
        found.tableRows.length ? `largest has ${plural(best, 'row', 'rows')}` : 'no table yet');
    }
    case 'emphasis':
      return make('Emphasis', found.emphasis > 0, found.emphasis > 0 ? 'found' : 'not yet');
    case 'strong':
      return make('Strong emphasis', found.strong > 0, found.strong > 0 ? 'found' : 'not yet');
    case 'words':
      return make(`At least ${check.min} words`, found.words >= check.min, plural(found.words, 'word', 'words'));
  }
}
