// ========================================
// Loomings — the learner's checker
// Gentle notes on common Markdown mistakes, each with the reason and, where
// safe, a one-click fix. The rule ids, messages and fixes match the native
// app (macos/Sources/LoomingsTeaching/MarkdownLint.swift); both pass
// macos/Tests/LoomingsTeachingTests/Fixtures/lint-cases.json. Pure: no DOM.
// ========================================

import { parseSource } from './parse.js';

/**
 * @typedef {{from: number, to: number, insert: string, title: string}} LintFix
 * @typedef {{rule: string, from: number, to: number, message: string, fix?: LintFix}} LintIssue
 */

export const MESSAGES = {
  'heading-space': 'A heading needs a space after its # signs; without one this line stays a paragraph.',
  'accidental-setext': 'A line of hyphens under text turns that text into a heading. For a horizontal rule, leave a blank line above the hyphens.',
  'unclosed-fence': 'This code block is never closed, so everything after it is code. End it with a line of the same fence.',
  'ordered-list-interrupt': 'A numbered list that does not start at 1 cannot begin in the middle of a paragraph. Leave a blank line above it.',
  'link-space': 'A link address cannot contain spaces unless it is wrapped in < and >.',
  'image-alt': 'This image has no alternative text. Describe it between the square brackets for readers who cannot see it.',
  'unpaired-emphasis': 'These marks did not pair up, so they show as written. Close them with the same marks after the text.',
  'table-separator': 'A table needs a separator row of hyphens under its first row, like | --- | --- |.',
};

const ORDERED_MARKER = /^ {0,3}(\d{1,9})[.)][ \t]+\S/;
const SPACED_LINK = /\[[^\]\n]+\]\(([^)\s<>"']+(?:[ \t]+[^)\s<>"']+)+)\)/g;

/**
 * @param {string} source
 * @param {ReturnType<typeof parseSource>} [parsed] a parse of `source` to reuse
 * @returns {LintIssue[]}
 */
export function lint(source, parsed) {
  if (!source) return [];
  const doc = parsed || parseSource(source);
  const { lines, tokens, lineEnding: nl } = doc;
  /** @type {LintIssue[]} */
  const issues = [];
  /** @type {{from: number, to: number}[]} */
  const codeSpans = [];
  /** @type {{first: number, last: number, from: number}[]} */
  const paragraphs = [];

  /** @param {string} rule @param {number} from @param {number} to @param {LintFix} [fix] */
  const add = (rule, from, to, fix) => {
    issues.push(fix ? { rule, from, to, message: MESSAGES[rule], fix } : { rule, from, to, message: MESSAGES[rule] });
  };

  let row = 0;
  for (let t = 0; t < tokens.length; t++) {
    const token = tokens[t];
    if (token.type === 'tr_open' && token.map) row = token.map[0];
    if (token.type === 'paragraph_open' && token.map) {
      const inline = tokens[t + 1];
      const first = token.map[0];
      const line = lines[first];
      const toSource = doc.mapper.forInline(inline, false);
      const from = toSource(0);
      // Only a paragraph at the start of its line (not in a list item or a
      // quotation) can be read line by line as written.
      if (/^ {0,3}$/.test(source.slice(line.from, from))) {
        paragraphs.push({ first, last: token.map[1] - 1, from });
      }
    } else if (token.type === 'heading_open' && token.map && (token.markup === '-' || token.markup === '=')) {
      // The note starts at the heading's text, as cmark's range does.
      checkSetext(token.map[0], token.map[1] - 1, doc.mapper.forInline(tokens[t + 1], false)(0));
    } else if (token.type === 'fence' && token.map) {
      checkFence(token.map[0], token.map[1] - 1);
    } else if (token.type === 'inline' && token.children) {
      const previous = tokens[t - 1];
      const ordered = previous && (previous.type === 'th_open' || previous.type === 'td_open'
        || (previous.type === 'heading_open' && previous.markup.startsWith('#')));
      checkInline(token, doc.mapper.forInline(token, !!ordered, row));
    }
  }

  for (const paragraph of paragraphs) checkParagraph(paragraph);
  return issues.sort((a, b) => a.from - b.from);

  // ---------- Blocks ----------

  /** Setext headings made with hyphens, when the text reads like prose. */
  function checkSetext(first, last, from) {
    if (lines[first].text.trim().startsWith('#')) return;
    const underline = lines[last].text.trim();
    if (underline[0] !== '-' || last <= first) return;
    const content = source.slice(lines[first].from, lines[last].from).trim();
    const multiline = content.includes('\n');
    const prose = '.,;:'.includes(content.slice(-1)) && content.length > 0;
    if (!multiline && !prose) return;
    add('accidental-setext', from, lines[last].from + lines[last].text.length, {
      from: lines[last].from, to: lines[last].from, insert: nl, title: 'Add a blank line above',
    });
  }

  /** A fenced block that runs to the end of the document with no closing fence. */
  function checkFence(first, last) {
    const opening = lines[first].text;
    const indent = opening.length - opening.replace(/^ +/, '').length;
    const marker = opening[indent];
    if (indent > 3 || (marker !== '`' && marker !== '~')) return;
    let length = 0;
    while (opening[indent + length] === marker) length++;
    if (length < 3) return;
    const fence = marker.repeat(length);
    const end = lines[last].from + lines[last].text.length;
    if (end < doc.contentEnd) return;
    if (last > first) {
      const closing = lines[last].text.trim();
      if (closing.length >= fence.length && [...closing].every((c) => c === marker)) return;
    }
    const fix = indent === 0
      ? { from: source.length, to: source.length, insert: (source.endsWith('\n') ? '' : nl) + fence + nl, title: 'Close the code block' }
      : undefined;
    add('unclosed-fence', lines[first].from, lines[first].from + opening.length, fix);
  }

  // ---------- Inline ----------

  /**
   * @param {{children: import('markdown-it/lib/token.mjs').default[]|null}} inline
   * @param {(offset: number) => number} toSource
   */
  function checkInline(inline, toSource) {
    const children = inline.children || [];
    for (let i = 0; i < children.length; i++) {
      const child = children[i];
      const meta = child.meta || {};
      if (child.type === 'code_inline' && meta.pos !== undefined) {
        codeSpans.push({ from: toSource(meta.pos), to: toSource(meta.end) });
      } else if (child.type === 'image' && meta.pos !== undefined) {
        // Only the alternative text's own words count, as in the native app;
        // white space of any kind (a non-breaking space too) is not alt text.
        let alt = '';
        let level = 0;
        for (const part of child.children || []) {
          if (part.nesting === -1) level--;
          if (level === 0 && (part.type === 'text' || part.type === 'text_special')) alt += part.content;
          if (part.nesting === 1) level++;
        }
        if (!alt.replace(/\s/g, '')) add('image-alt', toSource(meta.pos), toSource(meta.end));
        // The alt text is parsed on its own: its offsets count from after "![".
        const start = meta.pos + 2;
        checkInline(child, (offset) => toSource(start + offset));
      } else if (meta.delim && (child.content === '*' || child.content === '_') && child.type === 'text') {
        // A run of leftover marks: consecutive, one character apart.
        let j = i;
        while (j + 1 < children.length && children[j + 1].type === 'text' && children[j + 1].meta?.delim
          && children[j + 1].content === child.content && children[j + 1].meta.pos === children[j].meta.pos + 1) j++;
        if (j > i) add('unpaired-emphasis', toSource(meta.pos), toSource(meta.pos) + 2);
        i = j;
      }
    }
  }

  // ---------- Paragraph lines ----------

  function checkParagraph({ first, last, from }) {
    const span = [];
    for (let n = first; n <= last; n++) span.push(n);
    for (const n of span) {
      if (firstNonSpace(lines[n].text) === '#') checkHeadingSpace(n);
    }
    if (span.length > 1 && span.slice(1).some((n) => /\d/.test(firstNonSpace(lines[n].text)))) {
      checkOrderedInterrupt(span);
    }
    if (span.length > 1 && firstNonSpace(lines[first].text) === '|') checkTable(span);
    const to = lines[last].from + lines[last].text.length;
    if (source.slice(from, to).includes('](')) checkLinkSpaces(from, to);
  }

  /** The first character among the first four that is not a space, or ''. */
  function firstNonSpace(text) {
    for (let i = 0; i < 4 && i < text.length; i++) if (text[i] !== ' ') return text[i];
    return '';
  }

  function checkHeadingSpace(n) {
    const { text, from } = lines[n];
    const indent = text.length - text.replace(/^ +/, '').length;
    if (indent > 3) return;
    let hashes = 0;
    while (text[indent + hashes] === '#') hashes++;
    const next = text[indent + hashes];
    if (hashes < 1 || hashes > 6 || next === undefined || next === ' ' || next === '\t') return;
    const at = from + indent + hashes;
    add('heading-space', from, from + text.length, { from: at, to: at, insert: ' ', title: 'Add a space' });
  }

  function checkOrderedInterrupt(span) {
    for (const n of span.slice(1)) {
      const m = ORDERED_MARKER.exec(lines[n].text);
      if (!m || Number(m[1]) === 1) continue;
      const { from, text } = lines[n];
      add('ordered-list-interrupt', from, from + text.length, { from, to: from, insert: nl, title: 'Add a blank line above' });
      return;
    }
  }

  function checkTable(span) {
    const first = lines[span[0]].text.trim();
    const second = lines[span[1]].text.trim();
    if (first.length <= 1 || second.length <= 1) return;
    if (!first.startsWith('|') || !first.endsWith('|') || !second.startsWith('|') || !second.endsWith('|')) return;
    const columns = first.slice(1, -1).split('|').length;
    const row = '|' + ' --- |'.repeat(columns) + nl;
    const line = lines[span[0]];
    add('table-separator', line.from, line.from + line.text.length, {
      from: line.end, to: line.end, insert: row, title: 'Add the separator row',
    });
  }

  function checkLinkSpaces(from, to) {
    const text = source.slice(from, to);
    for (const m of text.matchAll(SPACED_LINK)) {
      const start = from + (m.index ?? 0);
      const end = start + m[0].length;
      if (codeSpans.some((c) => c.from < end && start < c.to)) continue;
      const address = start + m[0].indexOf('](') + 2;
      add('link-space', start, end, {
        from: address, to: address + m[1].length, insert: '<' + m[1] + '>', title: 'Wrap the address in < >',
      });
    }
  }
}
