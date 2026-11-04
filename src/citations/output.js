// ========================================
// Loomings — citation output
// Cleans citeproc HTML with an allowlist, turns it into Markdown and puts
// citations into a document. Citeproc output is untrusted: a title or a
// share link can carry any text. No tag reaches the DOM without this file.
// Pure: no DOM, no Node or browser APIs (JavaScriptCore runs it too).
// ========================================

import { SAFE_URL } from '../markdown.js';
import { parseSource } from '../teaching/parse.js';

/** @typedef {{from: number, to: number, html: string, markdown: string, missing: string[]}} CitationOutput */

const TAG = /<(\/?)([A-Za-z][A-Za-z0-9-]*)((?:"[^"]*"|'[^']*'|[^"'<>])*)>/g;
const INLINE = new Set(['i', 'b', 'sup', 'sub', 'span']);
const DIV_CLASSES = new Set(['csl-entry', 'csl-left-margin', 'csl-right-inline', 'csl-indent', 'csl-block']);
const HREF = /(?:^|\s)href\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))/i;
const CLASS = /(?:^|\s)class\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))/i;
const BLANKS = /[ \t\r\n\f\v\u0085\u2028\u2029]+/g;
const BREAK = /\r\n|\r|\n/g;

const escapeTag = (/** @type {string} */ text) => text.replace(/</g, '&lt;').replace(/>/g, '&gt;');

/** Text outside a tag: entities stay, and a bare `&` is escaped. */
function cleanText(text) {
  return escapeTag(text.replace(/&(?!#\d+;|#[xX][\da-fA-F]+;|[A-Za-z][A-Za-z0-9]*;)/g, '&amp;'));
}

/**
 * @param {RegExpExecArray|null} m
 * @returns {string|null}
 */
const attribute = (m) => (m ? m[1] ?? m[2] ?? m[3] : null);

/**
 * True for a link that citeproc made: it adds the doi.org base to each value
 * with no http scheme, also to a value in the URL field. The text then is the
 * href after the base, and it is not a DOI.
 *
 * @param {string} href
 * @param {string} html
 * @param {number} after  the offset after the opening tag
 */
function isFalseDoiLink(href, html, after) {
  const m = /^https:\/\/doi\.org\/(.+)$/.exec(href);
  return m !== null && !m[1].startsWith('10.') && html.startsWith(`${m[1]}</a>`, after);
}

/**
 * The tag to write for an opening tag.
 *
 * @param {string} name
 * @param {string} attrs
 * @param {string} html
 * @param {number} after
 * @returns {{open: string, close: string}|null}  null: the tag is text
 */
function allowedTag(name, attrs, html, after) {
  if (INLINE.has(name)) return { open: `<${name}>`, close: `</${name}>` };
  if (name === 'a') {
    const href = attribute(HREF.exec(attrs));
    if (href === null || !SAFE_URL.test(href) || isFalseDoiLink(href, html, after)) return { open: '', close: '' };
    return { open: `<a href="${escapeTag(href).replace(/"/g, '&quot;')}">`, close: '</a>' };
  }
  if (name === 'div') {
    const cls = attribute(CLASS.exec(attrs));
    if (cls !== null && DIV_CLASSES.has(cls)) return { open: `<div class="${cls}">`, close: '</div>' };
  }
  return null;
}

/**
 * Applies the allowlist. The output has balanced tags, so it cannot change
 * the page around it.
 *
 * @param {string} html
 * @returns {string}
 */
export function cleanCitationHtml(html) {
  const input = String(html ?? '');
  /** @type {{name: string, close: string, escaped: boolean}[]} */
  const open = [];
  // Counts the open tags by name, so a closing tag with no opening tag costs one step.
  const depth = new Map();
  const closeLast = () => {
    const entry = /** @type {{name: string, close: string, escaped: boolean}} */ (open.pop());
    depth.set(entry.name, depth.get(entry.name) - 1);
    return entry;
  };
  let out = '';
  let at = 0;
  TAG.lastIndex = 0;
  let m;
  while ((m = TAG.exec(input)) !== null) {
    out += cleanText(input.slice(at, m.index));
    at = TAG.lastIndex;
    const lower = m[2].toLowerCase();
    const name = lower === 'em' ? 'i' : lower;
    if (m[1]) {
      if (!depth.get(name)) {
        out += escapeTag(m[0]);
        continue;
      }
      while (open[open.length - 1].name !== name) out += closeLast().close;
      const entry = closeLast();
      out += entry.escaped ? escapeTag(m[0]) : entry.close;
      continue;
    }
    depth.set(name, (depth.get(name) ?? 0) + 1);
    const tag = allowedTag(name, m[3], input, at);
    if (tag) {
      out += tag.open;
      open.push({ name, close: tag.close, escaped: false });
    } else {
      out += escapeTag(m[0]);
      open.push({ name, close: '', escaped: true });
    }
  }
  out += cleanText(input.slice(at));
  while (open.length) out += closeLast().close;
  return out;
}

const NAMED = /** @type {Record<string, string>} */ ({ amp: '&', lt: '<', gt: '>', quot: '"', apos: "'" });
const SUPERSCRIPT = /** @type {Record<string, string>} */ ({
  0: '⁰', 1: '¹', 2: '²', 3: '³', 4: '⁴', 5: '⁵', 6: '⁶', 7: '⁷', 8: '⁸', 9: '⁹',
  '+': '⁺', '-': '⁻', '–': '⁻', '−': '⁻', '=': '⁼', '(': '⁽', ')': '⁾',
});
// A comma and a space stay as they are between superscript digits: citeproc
// joins numbers with them, and they have no superscript form.
const SUPERSCRIPT_RUN = /^[0-9+\-–−=(), ]*$/;

/** Superscript forms for the whole run, or the plain text. No run has mixed forms. */
function superscript(text) {
  return SUPERSCRIPT_RUN.test(text) ? text.replace(/[^, ]/g, (c) => SUPERSCRIPT[c]) : text;
}

/** Decodes each entity once. An entity with no valid character stays. */
function decodeEntities(text) {
  return text.replace(/&(?:#(\d+)|#[xX]([\da-fA-F]+)|(amp|lt|gt|quot|apos));/g, (all, dec, hex, named) => {
    if (named) return NAMED[named];
    const code = dec ? Number(dec) : parseInt(hex, 16);
    return code > 0 && code <= 0x10ffff ? String.fromCodePoint(code) : all;
  });
}

function escapeMarkdown(text) {
  return text.replace(/[\\`*_[\]<]/g, '\\$&').replace(/&(?=#?\w+;)/g, '\\&');
}

/** Writes emphasis marks tight around the text, as CommonMark needs them. */
function wrap(text, mark) {
  const core = text.trim();
  if (!core) return text;
  const start = text.length - text.trimStart().length;
  return `${text.slice(0, start)}${mark}${core}${mark}${text.slice(start + core.length)}`;
}

/**
 * @param {string} name
 * @param {string} href
 * @param {string} text
 * @param {boolean} nested  the same tag is open outside this one
 * @returns {string}
 */
function closeMarkdown(name, href, text, nested) {
  if (name === 'i') return nested ? text : wrap(text, '*');
  if (name === 'b') return nested ? text : wrap(text, '**');
  if (name === 'sup') return superscript(text);
  if (name === 'div') return `${text} `;
  if (name !== 'a' || !text.trim()) return text;
  const target = decodeEntities(href);
  if (text.trim() === escapeMarkdown(target)) return text;
  return `[${text.trim()}](${target.replace(/[\\()]/g, '\\$&').replace(/\s/g, '%20')})`;
}

/**
 * One line of Markdown from citation HTML.
 *
 * @param {string} html
 * @returns {string}
 */
export function toMarkdown(html) {
  const input = cleanCitationHtml(html);
  const frames = [{ name: '', href: '', text: '' }];
  const top = () => frames[frames.length - 1];
  const depth = new Map();
  const add = (/** @type {string} */ raw) => {
    top().text += escapeMarkdown(decodeEntities(raw).replace(BLANKS, ' '));
  };
  let at = 0;
  TAG.lastIndex = 0;
  let m;
  while ((m = TAG.exec(input)) !== null) {
    add(input.slice(at, m.index));
    at = TAG.lastIndex;
    if (!m[1]) {
      frames.push({ name: m[2], href: attribute(HREF.exec(m[3])) ?? '', text: '' });
      depth.set(m[2], (depth.get(m[2]) ?? 0) + 1);
    } else {
      const frame = /** @type {{name: string, href: string, text: string}} */ (frames.pop());
      const outside = depth.get(frame.name) - 1;
      depth.set(frame.name, outside);
      top().text += closeMarkdown(frame.name, frame.href, frame.text, outside > 0);
    }
  }
  add(input.slice(at));
  return top().text
    .replace(/ {2,}/g, ' ')
    .trim()
    .replace(/^(\d+)([.)])/, '$1\\$2')
    .replace(/^[-+#>]/, '\\$&');
}

/**
 * Replaces each citation range. A one-line text gets the line breaks of its
 * range after it, so each later line stays at its number.
 *
 * @param {string} source
 * @param {{from: number, to: number}[]} citations
 * @param {(index: number) => string} text
 * @returns {string}
 */
function replaceRanges(source, citations, text) {
  let out = '';
  let at = 0;
  citations.forEach((c, i) => {
    const next = text(i);
    const breaks = /[\r\n]/.test(next) ? [] : source.slice(c.from, c.to).match(BREAK) ?? [];
    out += source.slice(at, c.from) + next + breaks.join('');
    at = c.to;
  });
  return out + source.slice(at);
}

const FENCE_LINE = /^ {0,3}(`+|~+)[ \t]*$/;

/**
 * The marker that closes the final fence of a text, or null when no fence is
 * open. An open fence runs to the end of the text, so it is the last token. A
 * fence in a list or a quotation ends at the blank line before the references.
 *
 * @param {string} text
 * @returns {string|null}
 */
function openFence(text) {
  if (!text.includes('```') && !text.includes('~~~')) return null;
  const { tokens, lines } = parseSource(text);
  const last = tokens[tokens.length - 1];
  if (last?.type !== 'fence' || last.level !== 0 || !last.map) return null;
  const end = last.map[1] - 1;
  const closing = end > last.map[0] ? FENCE_LINE.exec(lines[end].text)?.[1] : undefined;
  const closed = closing !== undefined && closing[0] === last.markup[0] && closing.length >= last.markup.length;
  return closed ? null : last.markup;
}

/**
 * The document for a Markdown renderer: each citation as Markdown, then the
 * title and the entries. A closing line for an open final fence comes after
 * the last source line, so each source line stays at its number.
 *
 * @param {string} source
 * @param {CitationOutput[]} citations
 * @param {string|null} title
 * @param {string} bibliographyMarkdown
 * @returns {string}
 */
export function withReferences(source, citations, title, bibliographyMarkdown) {
  const text = replaceRanges(source, citations, (i) => citations[i].markdown);
  if (!bibliographyMarkdown) return text;
  const endsLine = /[\r\n]$/.test(text);
  const fence = openFence(text);
  const body = fence === null ? text : `${text}${endsLine ? '' : '\n'}${fence}\n`;
  const gap = fence !== null || endsLine ? '\n' : '\n\n';
  return `${body}${gap}${title ? `## ${title}\n\n` : ''}${bibliographyMarkdown}`;
}

/** Two private-use characters that the source does not contain. */
function markerPair(source) {
  let code = 0xe000;
  while (source.includes(String.fromCharCode(code)) || source.includes(String.fromCharCode(code + 1))) code += 2;
  return [String.fromCharCode(code), String.fromCharCode(code + 1)];
}

/**
 * Prepares a source for the web renderer. Each citation becomes a private-use
 * marker with the same line count. `fill` puts the citations into the
 * rendered HTML. A marker inside a tag (image alt text) gets plain text.
 *
 * @param {string} source
 * @param {{citations: CitationOutput[]}} report
 * @returns {{text: string, fill(html: string): string}}
 */
export function applyCitations(source, report) {
  const { citations } = report;
  const [open, close] = markerPair(source);
  const text = replaceRanges(source, citations, (i) => `${open}${i}${close}`);
  const marker = `${open}(\\d+)${close}`;
  const inTag = new RegExp(marker, 'g');
  const pieces = new RegExp(`<[^>]*>|${marker}`, 'g');
  const plain = (/** @type {string} */ n) => citations[Number(n)].html.replace(/<[^>]*>/g, '').replace(/"/g, '&quot;');
  const span = (/** @type {string} */ n) => {
    const c = citations[Number(n)];
    return `<span class="cite${c.missing.length ? ' cite-missing' : ''}">${c.html}</span>`;
  };
  return {
    text,
    fill: (html) => html.replace(pieces, (piece, n) =>
      (n === undefined ? piece.replace(inTag, (_, inner) => plain(inner)) : span(n))),
  };
}
