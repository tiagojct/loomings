// ========================================
// Loomings — citations in the editor (web only)
// Colours for the citations, the notes of the citation report and completion
// of keys after `@`. The editor gets the report through a function, so this
// file does not know the worker or the document glue.
// ========================================

import { RangeSetBuilder, StateEffect } from '@codemirror/state';
import { Decoration, ViewPlugin } from '@codemirror/view';
import { autocompletion } from '@codemirror/autocomplete';
import { ensureSyntaxTree, syntaxTree } from '@codemirror/language';
import { foldText } from '../accents.js';
import { frontmatterRange } from '../teaching/glossary.js';

/**
 * @typedef {import('./session.js').CitationReport} CitationReport
 * @typedef {import('./session.js').LibraryEntry} LibraryEntry
 * @typedef {{title: string, kind: 'add-file'}} NoteAction
 * @typedef {{from: number, to: number, message: string, rule: string, fileLevel?: boolean,
 *   action?: NoteAction}} CitationLintNote
 */

/** The editor sends this when a new citation report is in place. It changes no text. */
export const citationReportEffect = /** @type {import('@codemirror/state').StateEffectType<null>} */ (StateEffect.define());

const CODE_NODES = new Set(['InlineCode', 'FencedCode', 'CodeBlock', 'CodeText']);
const KEY_BEFORE = /[\p{L}\p{N}_\\]/u;
const MAX_OPTIONS = 100;

/**
 * Completion of a citation key. The text after the last `@` is the query. It
 * can have spaces: each word must be in the key, the authors or the title.
 *
 * @param {import('@codemirror/autocomplete').CompletionContext} context
 * @param {LibraryEntry[]|(() => LibraryEntry[])} library
 * @returns {import('@codemirror/autocomplete').CompletionResult|null}
 */
export function citationCompletions(context, library) {
  const typed = context.matchBefore(/@[^@[\]\n;]{0,40}/u);
  if (!typed) return null;
  const line = context.state.doc.lineAt(typed.from);
  const before = typed.from > line.from ? line.text[typed.from - line.from - 1] : '';
  // A letter before the sign: an email address. A backslash: an escaped sign.
  if (before && KEY_BEFORE.test(before)) return null;

  const frontmatter = frontmatterRange(context.state.doc);
  if (frontmatter && typed.from <= frontmatter.to) return null;
  const tree = ensureSyntaxTree(context.state, context.pos, 20) ?? syntaxTree(context.state);
  for (let node = /** @type {import('@lezer/common').SyntaxNode|null} */ (tree.resolveInner(context.pos, -1)); node; node = node.parent) {
    if (CODE_NODES.has(node.name)) return null;
  }

  const entries = typeof library === 'function' ? library() : library;
  const words = foldText(typed.text.slice(1)).split(/\s+/).filter(Boolean);
  const options = [];
  for (const entry of entries) {
    const haystack = foldText(`${entry.key} ${entry.authors} ${entry.title}`);
    if (!words.every((w) => haystack.includes(w))) continue;
    options.push({
      label: entry.key,
      apply: entry.key,
      detail: [entry.authors, entry.year].filter(Boolean).join(' '),
      info: entry.title || undefined,
    });
    if (options.length >= MAX_OPTIONS) break;
  }
  if (!options.length) return null;
  return { from: typed.from + 1, options, filter: false };
}

/**
 * The ranges to colour. A range past the end of the text is cut to it.
 *
 * @param {Pick<CitationReport, 'citations'>|null} report
 * @param {number} length  the length of the text
 * @returns {{from: number, to: number, missing: boolean}[]}
 */
export function citationRanges(report, length) {
  if (!report) return [];
  return report.citations
    .map((c) => ({ from: Math.min(c.from, length), to: Math.min(c.to, length), missing: (c.missing?.length ?? 0) > 0 }))
    .filter((r) => r.from < r.to);
}

const MISSING_FILE = /^The file (.+) is missing\.$/;

/**
 * The notes of a report, in the format of the checker's notes. A note about
 * a file has no place in the text, so it has no line to go to. The ranges
 * are cut to the text, because the report can be for an older text.
 *
 * @param {Pick<CitationReport, 'notes'>|null} report
 * @param {number} length  the length of the text
 * @returns {CitationLintNote[]}
 */
export function citationNotes(report, length) {
  if (!report) return [];
  return report.notes.map((note) => {
    const from = Math.min(note.from, length);
    const to = Math.min(note.to, length);
    if (note.from !== 0 || note.to !== 0) return { from, to, message: note.message, rule: 'citation' };
    const missing = MISSING_FILE.exec(note.message);
    if (missing) {
      return {
        from: 0, to: 0, rule: 'citation', fileLevel: true,
        message: `No file called ${missing[1]} in this browser.`,
        action: { title: `Add ${missing[1]}`, kind: 'add-file' },
      };
    }
    const place = note.file ? `${note.file}${note.line ? `, line ${note.line + 1}` : ''}: ` : '';
    return { from: 0, to: 0, rule: 'citation', fileLevel: true, message: place + note.message };
  });
}

/** The rules for makeTheme. Colours come from the palette roles. */
export function citationThemeRules(/** @type {Record<string, string>} */ p) {
  return {
    '.cm-citation': { color: p.marker },
    '.cm-citation-missing': { color: p.marker, textDecoration: 'underline dotted', textUnderlineOffset: '3px' },
    '.cm-tooltip.cm-tooltip-autocomplete': {
      backgroundColor: p.bgElev, color: p.fg, border: `1px solid ${p.border}`, borderRadius: '4px',
    },
    '.cm-tooltip-autocomplete > ul': { fontFamily: "'JetBrains Mono', 'SF Mono', monospace", fontSize: '13px' },
    '.cm-tooltip-autocomplete > ul > li': { color: p.fg },
    '.cm-tooltip-autocomplete > ul > li[aria-selected]': { backgroundColor: p.selection + ' !important', color: p.fg + ' !important' },
    '.cm-completionDetail': { color: p.fgDim, fontStyle: 'normal', marginLeft: '0.8em' },
    '.cm-completionMatchedText': { textDecoration: 'none', color: p.accentLight },
    '.cm-tooltip.cm-completionInfo': {
      backgroundColor: p.bgElev, color: p.fgDim, border: `1px solid ${p.border}`, padding: '4px 8px',
    },
  };
}

const citationMark = Decoration.mark({ class: 'cm-citation' });
const missingMark = Decoration.mark({ class: 'cm-citation-missing' });

/**
 * @param {(text: string) => CitationReport|null} getReport  the report for this text
 * @param {() => LibraryEntry[]} getLibrary  a cheap read: completion calls it on each keystroke
 * @returns {import('@codemirror/state').Extension[]}
 */
export function citationExtensions(getReport, getLibrary) {
  // The ranges move with the edits. A new report sets them again, so a range
  // is right again when the report for the new text is in place.
  const plugin = ViewPlugin.fromClass(class {
    /** @param {import('@codemirror/view').EditorView} view */
    constructor(view) {
      // The first ranges come with the first report effect: the report holder can be not ready here.
      /** @type {{from: number, to: number, missing: boolean}[]} */
      this.ranges = [];
      this.decorations = this.build(view);
    }

    /** @param {import('@codemirror/view').ViewUpdate} update */
    update(update) {
      const fresh = update.transactions.some((tr) => tr.effects.some((e) => e.is(citationReportEffect)));
      if (fresh) {
        this.ranges = citationRanges(getReport(update.state.doc.toString()), update.state.doc.length);
      } else if (update.docChanged) {
        this.ranges = this.ranges
          .map((r) => ({ ...r, from: update.changes.mapPos(r.from, 1), to: update.changes.mapPos(r.to, -1) }))
          .filter((r) => r.from < r.to);
      }
      if (fresh || update.docChanged || update.viewportChanged) this.decorations = this.build(update.view);
    }

    /** @param {import('@codemirror/view').EditorView} view */
    build(view) {
      const visible = view.visibleRanges;
      const builder = /** @type {RangeSetBuilder<Decoration>} */ (new RangeSetBuilder());
      for (const r of this.ranges) {
        if (!visible.some((v) => r.from < v.to && v.from < r.to)) continue;
        builder.add(r.from, r.to, r.missing ? missingMark : citationMark);
      }
      return builder.finish();
    }
  }, { decorations: (v) => v.decorations });

  return [
    plugin,
    autocompletion({
      override: [(context) => citationCompletions(context, getLibrary)],
      activateOnTyping: true,
      icons: false,
    }),
  ];
}
