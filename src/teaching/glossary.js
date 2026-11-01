// ========================================
// Loomings — explain this marker
// What a Markdown marker does and which lesson teaches it. The wording
// matches the native app (macos/Sources/LoomingsTeaching/MarkerGlossary.swift);
// both pass macos/Tests/LoomingsTeachingTests/Fixtures/glossary-cases.json.
// `markerAt` finds the marker under a position in the editor's syntax tree.
// ========================================

import { syntaxTree } from '@codemirror/language';

/** @typedef {{title: string, body: string, lesson: string|null}} Explanation */
/** @typedef {{kind: string, marker: string, from: number, to: number}} Marker */

export const KINDS = [
  'headingMarker', 'emphasisMarker', 'strongMarker', 'strikethroughMarker', 'inlineCodeMarker',
  'fencedCodeDelimiter', 'blockQuoteMarker', 'listMarker', 'linkPunctuation', 'imagePunctuation',
  'thematicBreak', 'rawHTML', 'frontmatter',
];

const BASICS = '01-basics.md';
const LISTS = '02-lists-quotes.md';
const LINKS = '03-links-images.md';
const CODE = '04-code.md';

/**
 * @param {string} kind one of KINDS (or codeBlockContent, which has none)
 * @param {string} marker the marker as written
 * @returns {Explanation|null}
 */
export function explain(kind, marker) {
  const mark = marker.replace(/^[ \t]+|[ \t]+$/g, '');
  /** @type {(title: string, body: string, lesson: string|null) => Explanation} */
  const make = (title, body, lesson) => ({ title, body, lesson });
  switch (kind) {
    case 'headingMarker': {
      if (mark[0] === '=') {
        return make('Level-1 heading (underline)',
          'A line of = signs under text makes that text a level-1 heading. A line of hyphens makes a level-2 heading.', BASICS);
      }
      if (mark[0] === '-') {
        return make('Level-2 heading (underline)',
          'A line of hyphens directly under text makes that text a level-2 heading. For a horizontal rule, leave a blank line above the hyphens.', BASICS);
      }
      const level = Math.min(6, Math.max(1, [...mark].filter((c) => c === '#').length));
      const signs = level === 1 ? 'One # sign' : `${level} # signs`;
      return make(`Level-${level} heading`,
        `${signs} and a space start a level-${level} heading. One # is the title of the document, two a section, three a subsection.`, BASICS);
    }
    case 'emphasisMarker':
      return make('Emphasis', 'One * or _ on each side of a word sets it in italics.', BASICS);
    case 'strongMarker':
      return make('Strong emphasis', 'Two * or _ on each side of a word set it in bold.', BASICS);
    case 'strikethroughMarker':
      return make('Strikethrough', 'Two ~ on each side of a word draw a line through it.', null);
    case 'inlineCodeMarker':
      return make('Inline code',
        'Backticks show the text between them exactly as typed, in a code face. Markdown inside them is not read.', CODE);
    case 'fencedCodeDelimiter':
      return make('Code block fence',
        'A line of three backticks or tildes opens a code block and another closes it. A language name may follow the opening fence.', CODE);
    case 'blockQuoteMarker':
      return make('Quotation', 'A > at the start of a line quotes the text after it. Quotations can hold several paragraphs.', LISTS);
    case 'listMarker':
      if (mark.startsWith('[')) {
        return make('Task box', '[ ] after a list marker is an open task; [x] is a finished one.', LISTS);
      }
      if (/^[0-9]/.test(mark)) {
        return make('Numbered list item',
          'A number, a full stop or bracket, and a space start a numbered item. The numbers need not be in order; the result counts on from the first.', LISTS);
      }
      return make('Bullet list item',
        'A hyphen, asterisk or plus sign and a space start a bullet item. Indent an item to put it inside the one above.', LISTS);
    case 'linkPunctuation':
      return make('Link', 'Square brackets hold the text to show; the parentheses after them hold the address.', LINKS);
    case 'imagePunctuation':
      return make('Image', 'Like a link with ! in front. The brackets hold the alternative text that describes the image.', LINKS);
    case 'thematicBreak':
      return make('Horizontal rule',
        'Three or more hyphens, asterisks or underscores on a line of their own draw a rule across the page.', '05-tables-rules.md');
    case 'rawHTML':
      return make('HTML', 'Loomings shows HTML as written. The preview never runs it.', null);
    case 'frontmatter':
      return make('Frontmatter',
        'The block between two lines of --- at the very top holds facts about the document, such as its title. It is not shown in the result.', '06-frontmatter.md');
    default:
      return null;
  }
}

const HTML_NODES = new Set(['HTMLTag', 'HTMLBlock', 'Comment', 'CommentBlock', 'ProcessingInstruction', 'ProcessingInstructionBlock']);
const CODE_NODES = new Set(['InlineCode', 'FencedCode', 'CodeBlock', 'CodeText']);
const TASK_BOX = /^(\s*(?:[-*+]|\d{1,9}[.)])[ \t]+)(\[[ xX]\])(?=\s|$)/;

/**
 * The marker under `pos` (a position between characters; the character on
 * either side counts), or null.
 *
 * @param {import('@codemirror/state').EditorState} state
 * @param {number} pos
 * @returns {Marker|null}
 */
export function markerAt(state, pos) {
  const doc = state.doc;
  const tree = syntaxTree(state);

  // Frontmatter, as the native app reads it: --- on line 1, --- by line 50.
  if (doc.lines >= 2 && doc.line(1).text === '---') {
    for (let n = 2; n <= Math.min(doc.lines, 50); n++) {
      const line = doc.line(n);
      if (line.text === '---') {
        if (pos <= line.to) return { kind: 'frontmatter', marker: '---', from: 0, to: line.to };
        break;
      }
    }
  }

  const insideCode = (/** @type {number} */ at) => {
    for (let node = /** @type {import('@lezer/common').SyntaxNode|null} */ (tree.resolve(at, 1)); node; node = node.parent) {
      if (CODE_NODES.has(node.name)) return true;
    }
    return false;
  };

  // Task boxes and strikethrough are GFM; the editor's grammar is CommonMark.
  const line = doc.lineAt(pos);
  const task = TASK_BOX.exec(line.text);
  if (task) {
    const from = line.from + task[1].length;
    if (pos >= from && pos <= from + 3) return { kind: 'listMarker', marker: task[2], from, to: from + 3 };
  }
  const tilde = (/** @type {number} */ at) => at >= line.from && at < line.to && doc.sliceString(at, at + 1) === '~';
  if (tilde(pos) || tilde(pos - 1)) {
    let from = tilde(pos) ? pos : pos - 1;
    let to = from + 1;
    while (tilde(from - 1)) from--;
    while (tilde(to)) to++;
    if (to - from === 2 && !insideCode(from)) return { kind: 'strikethroughMarker', marker: '~~', from, to };
  }

  for (const side of /** @type {const} */ ([1, -1])) {
    const node = tree.resolve(pos, side);
    const found = classify(node);
    if (found) return { ...found, from: node.from, to: node.to };
  }
  return null;

  /** @param {import('@lezer/common').SyntaxNode} node */
  function classify(node) {
    const text = doc.sliceString(node.from, node.to);
    const parent = node.parent?.name || '';
    switch (node.name) {
      case 'HeaderMark':
        return { kind: 'headingMarker', marker: text };
      case 'EmphasisMark':
        return { kind: parent === 'StrongEmphasis' ? 'strongMarker' : 'emphasisMarker', marker: text };
      case 'CodeMark':
        return parent === 'InlineCode' ? { kind: 'inlineCodeMarker', marker: text } : { kind: 'fencedCodeDelimiter', marker: text };
      case 'CodeInfo': {
        const fence = node.parent?.firstChild;
        return { kind: 'fencedCodeDelimiter', marker: fence ? doc.sliceString(fence.from, fence.to) : '```' };
      }
      case 'LinkMark':
      case 'URL':
        if (parent === 'Image') return { kind: 'imagePunctuation', marker: text };
        if (parent === 'Link') return { kind: 'linkPunctuation', marker: text };
        return null;
      case 'ListMark':
        return { kind: 'listMarker', marker: text + ' ' };
      case 'QuoteMark':
        return { kind: 'blockQuoteMarker', marker: text };
      case 'HorizontalRule':
        return { kind: 'thematicBreak', marker: text };
      default:
        return HTML_NODES.has(node.name) ? { kind: 'rawHTML', marker: text } : null;
    }
  }
}
