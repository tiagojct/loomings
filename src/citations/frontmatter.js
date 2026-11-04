// ========================================
// Loomings — citation frontmatter keys
// Reads and writes `bibliography`, `csl`, `lang`, `reference-section-title`
// and `references` in the leading frontmatter. Line based, no YAML library.
// Pure: no DOM, no Node or browser APIs (JavaScriptCore runs it too).
// ========================================

import { splitLines, frontmatterLines } from '../teaching/parse.js';

/**
 * @typedef {{bibliography: string[], csl: string|null, lang: string|null,
 *   title: string|null, references: Record<string, unknown>[], referencesDropped: number}} CitationMeta
 *   referencesDropped: the entries removed because they have no string id, or
 *   -1 when the value of `references` is not a JSON list.
 * @typedef {import('../teaching/parse.js').SourceLine} SourceLine
 */

const KEY = /^([A-Za-z][\w-]*)[ \t]*:(.*)$/;
const ITEM = /^[ \t]*-(?:[ \t]+(.*))?$/;

/**
 * Find a key line inside the frontmatter. A key owns the list items and
 * indented lines that follow it.
 *
 * @param {SourceLine[]} lines
 * @param {number} last  index of the closing line
 * @param {string} key
 * @returns {{start: number, end: number, rest: string}[]}  end: last line of the block
 */
function findKey(lines, last, key) {
  /** @type {{start: number, end: number, rest: string}[]} */
  const found = [];
  for (let n = 1; n < last; n++) {
    const m = KEY.exec(lines[n].text);
    if (!m || m[1] !== key) continue;
    let end = n;
    let flow = false;
    // The value of `references` is JSON, so a number sign in a title is text.
    const open = (key === 'references' ? stripJsonComment : stripComment)(m[2]).trim();
    if (open[0] === '[' && open[open.length - 1] !== ']') {
      // A flow list can go on over lines of any indent, up to its closing bracket.
      let joined = open;
      for (let k = n + 1; k < last; k++) {
        joined += ' ' + stripComment(lines[k].text).trim();
        if (joined[joined.length - 1] === ']') {
          end = k;
          flow = true;
          break;
        }
      }
    }
    while (!flow && end + 1 < last && (ITEM.test(lines[end + 1].text) || /^[ \t]+\S/.test(lines[end + 1].text))) end++;
    found.push({ start: n, end, rest: m[2] });
    n = end;
  }
  return found;
}

/** Remove a comment that starts with whitespace and `#`, outside quotes. */
function stripComment(text) {
  let quote = '';
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quote) {
      if (c === '\\' && quote === '"') i++;
      else if (c === quote) quote = '';
    } else if (c === '"' || c === "'") {
      if (i === 0 || /[\s[,]/.test(text[i - 1])) quote = c;
    } else if (c === '#' && (i === 0 || /\s/.test(text[i - 1]))) {
      return text.slice(0, i);
    }
  }
  return text;
}

/** Remove a comment after a JSON value: whitespace and `#` outside a string. */
function stripJsonComment(text) {
  let inString = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (inString) {
      if (c === '\\') i++;
      else if (c === '"') inString = false;
    } else if (c === '"') {
      inString = true;
    } else if (c === '#' && (i === 0 || /\s/.test(text[i - 1]))) {
      return text.slice(0, i);
    }
  }
  return text;
}

/** True when the text is one flow list with no nested brackets. */
function isFlowList(text) {
  if (text.length < 2 || text[0] !== '[' || text[text.length - 1] !== ']') return false;
  const body = text.slice(1, -1);
  let quote = '';
  for (let i = 0; i < body.length; i++) {
    const c = body[i];
    if (quote) {
      if (c === '\\' && quote === '"') i++;
      else if (c === quote) quote = '';
    } else if (c === '"' || c === "'") {
      if (i === 0 || /[\s[,]/.test(body[i - 1])) quote = c;
    } else if (c === '[' || c === ']') {
      return false;
    } else if (c === '#' && (i === 0 || /\s/.test(body[i - 1]))) {
      return false;
    }
  }
  return quote === '';
}

/** One scalar: trimmed, with matching quotes removed. */
function unquote(text) {
  const t = text.trim();
  if (t.length >= 2 && t[0] === '"' && t[t.length - 1] === '"') {
    try {
      const v = JSON.parse(t);
      if (typeof v === 'string') return v;
    } catch {
      /* fall through to the plain strip */
    }
    return t.slice(1, -1);
  }
  if (t.length >= 2 && t[0] === "'" && t[t.length - 1] === "'") return t.slice(1, -1).replace(/''/g, "'");
  return t;
}

/** Split a flow list body on commas outside quotes. */
function splitFlow(body) {
  /** @type {string[]} */
  const parts = [];
  let quote = '';
  let from = 0;
  for (let i = 0; i < body.length; i++) {
    const c = body[i];
    if (quote) {
      if (c === '\\' && quote === '"') i++;
      else if (c === quote) quote = '';
    } else if (c === '"' || c === "'") {
      if (i === 0 || /[\s[,]/.test(body[i - 1])) quote = c;
    } else if (c === ',') {
      parts.push(body.slice(from, i));
      from = i + 1;
    }
  }
  parts.push(body.slice(from));
  return parts;
}

/**
 * The values of a key as a list: a scalar, a flow list or a block list.
 *
 * @param {SourceLine[]} lines
 * @param {{start: number, end: number, rest: string}} entry
 * @returns {string[]}
 */
function listValue(lines, entry) {
  let rest = stripComment(entry.rest).trim();
  if (rest[0] === '[' && rest[rest.length - 1] !== ']') {
    for (let n = entry.start + 1; n <= entry.end; n++) {
      rest += ' ' + stripComment(lines[n].text).trim();
      if (rest[rest.length - 1] === ']') break;
    }
    rest = rest.trim();
  }
  /** @type {string[]} */
  let values;
  if (rest === '') {
    values = [];
    for (let n = entry.start + 1; n <= entry.end; n++) {
      const m = ITEM.exec(lines[n].text);
      if (m && m[1] !== undefined) values.push(unquote(stripComment(m[1])));
    }
  } else if (rest[0] === '[' && rest[rest.length - 1] === ']') {
    values = splitFlow(rest.slice(1, -1)).map(unquote);
  } else {
    values = [unquote(rest)];
  }
  return values.filter((v) => v !== '');
}

/** @returns {string|null} */
function scalarValue(lines, entry) {
  const list = listValue(lines, entry);
  return list.length ? list[0] : null;
}

/**
 * @param {string} text
 * @returns {{entries: Record<string, unknown>[], dropped: number}}
 */
function parseReferences(text) {
  try {
    const value = JSON.parse(text);
    if (!Array.isArray(value)) return { entries: [], dropped: -1 };
    const entries = value.filter((e) => e !== null && typeof e === 'object' && !Array.isArray(e) && typeof e.id === 'string');
    return { entries, dropped: value.length - entries.length };
  } catch {
    return { entries: [], dropped: -1 };
  }
}

/**
 * The citation keys of the leading frontmatter.
 *
 * @param {string} source
 * @returns {CitationMeta}
 */
export function readCitationMeta(source) {
  /** @type {CitationMeta} */
  const meta = { bibliography: [], csl: null, lang: null, title: null, references: [], referencesDropped: 0 };
  const lines = splitLines(source);
  const fm = frontmatterLines(lines);
  if (!fm) return meta;
  const first = (key) => findKey(lines, fm.last, key)[0];
  const bib = first('bibliography');
  if (bib) meta.bibliography = listValue(lines, bib);
  const csl = first('csl');
  if (csl) meta.csl = scalarValue(lines, csl);
  const lang = first('lang');
  if (lang) meta.lang = scalarValue(lines, lang);
  const title = first('reference-section-title');
  if (title) meta.title = scalarValue(lines, title);
  const refs = first('references');
  if (refs) {
    const text = stripJsonComment(refs.rest).trim();
    // An empty key with no lines under it holds nothing, so nothing is dropped.
    if (text || refs.end > refs.start) {
      const parsed = parseReferences(text);
      meta.references = parsed.entries;
      meta.referencesDropped = parsed.dropped;
    }
  }
  return meta;
}

/** Quote a scalar when plain YAML would change its meaning. */
function formatScalar(value) {
  if (/^[\s"'[\]{}&*!|>%@`#,-]|\s$|\s#|: |:$|^$/.test(value)) return JSON.stringify(value);
  return value;
}

/**
 * Set or remove one key. `null` removes the key. A `bibliography` value that
 * is a well-formed flow list is written as it is. A value with a line break
 * throws, and so does a `references` value that is not a JSON array. A `references` value is
 * written as it is (one line of JSON). Other values are quoted when needed.
 * Without a frontmatter, one is made when the value is not null.
 *
 * @param {string} source
 * @param {'bibliography'|'csl'|'lang'|'references'} key
 * @param {string|null} value
 * @returns {string}
 */
export function setCitationMeta(source, key, value) {
  if (value !== null && /[\r\n\u2028\u2029]/.test(value)) {
    throw new Error(`setCitationMeta: the value of "${key}" has a line break.`);
  }
  if (key === 'references' && value !== null) {
    let ok = false;
    try {
      ok = Array.isArray(JSON.parse(value));
    } catch {
      /* not JSON */
    }
    if (!ok) throw new Error('setCitationMeta: "references" must be a JSON array on one line.');
  }
  const lines = splitLines(source);
  const fm = frontmatterLines(lines);
  const raw = key === 'references' || (key === 'bibliography' && value !== null && isFlowList(value));
  const text = value === null ? null : `${key}: ${raw ? value : formatScalar(value)}`;
  if (!fm) {
    if (text === null) return source;
    const eol = /\r\n|\n|\r/.exec(source);
    const nl = eol ? eol[0] : '\n';
    return `---${nl}${text}${nl}---${nl}${source}`;
  }
  const found = findKey(lines, fm.last, key);
  if (!found.length) {
    if (text === null) return source;
    if (fm.last + 1 >= 50) {
      throw new Error(`setCitationMeta: a new key would move the closing --- past line 50.`);
    }
    const close = lines[fm.last];
    const nl = source.slice(lines[fm.last - 1].text.length + lines[fm.last - 1].from, lines[fm.last - 1].end);
    return source.slice(0, close.from) + text + nl + source.slice(close.from);
  }
  // Rewrite from the last entry to the first so the offsets stay valid.
  let out = source;
  for (let i = found.length - 1; i >= 0; i--) {
    const e = found[i];
    const from = lines[e.start].from;
    const to = lines[e.end].end;
    const nl = out.slice(lines[e.end].from + lines[e.end].text.length, to);
    out = out.slice(0, from) + (i === 0 && text !== null ? text + nl : '') + out.slice(to);
  }
  return out;
}
