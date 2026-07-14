// ========================================
// Loomings — Editor (Tauri v2 + CodeMirror 6)
// ========================================

import { EditorState, Compartment, RangeSetBuilder, StateEffect } from '@codemirror/state';
import { EditorView, keymap, drawSelection, lineNumbers, placeholder, ViewPlugin, Decoration } from '@codemirror/view';
import { history, defaultKeymap, historyKeymap, indentWithTab } from '@codemirror/commands';
import { markdown } from '@codemirror/lang-markdown';
import { HighlightStyle, syntaxHighlighting, indentOnInput, bracketMatching, syntaxTree } from '@codemirror/language';
import { search, searchKeymap, openSearchPanel } from '@codemirror/search';
import { tags as t } from '@lezer/highlight';
import MarkdownIt from 'markdown-it';
import {
  isTauri, listen, getVersion, openUrl, ask,
  ipcSetTitle, ipcSaveFile, ipcSaveFileAs, ipcAddRecent, ipcSaveScratch,
  ipcReadScratch, ipcClearScratch, ipcConfirmQuit, ipcTakeLaunchFile,
  ipcFrontendReady, ipcWatchFile, ipcUnwatchFile, ipcSyncThemeMenu,
  ipcExportHtml, ipcOpenFile, ipcOpenExample, ipcCheckForUpdate,
  initTitlebarDrag, initDragDrop, getRecents, openRecent,
} from './platform.js';

const isMac = /Mac/i.test(navigator.platform) || /Mac/i.test(navigator.userAgent);

const editorEl    = document.getElementById('editor');
const preview     = document.getElementById('preview');
const contentArea = document.getElementById('content-area');
const dirtyEl     = document.getElementById('dirty');
const statsEl     = document.getElementById('stats');
const statWords   = document.getElementById('stat-words');
const statChars   = document.getElementById('stat-chars');
const statLines   = document.getElementById('stat-lines');
const statRead    = document.getElementById('stat-read');
const statusApp   = document.getElementById('status-app');
const statusFile  = document.getElementById('status-file');
const cursorPosEl = document.getElementById('cursor-pos');
const body        = document.body;

const STORE = {
  get(k, fb)      { try { const v = localStorage.getItem('loomings_' + k); return v !== null ? v : fb; } catch (_) { return fb; } },
  set(k, v)       { try { localStorage.setItem('loomings_' + k, v); } catch (_) {} },
  getBool(k, fb)  { return this.get(k, fb ? 'true' : 'false') === 'true'; },
  setBool(k, v)   { this.set(k, v ? 'true' : 'false'); },
  getNum(k, fb)   { const v = parseFloat(this.get(k, String(fb))); return isNaN(v) ? fb : v; }
};

let currentFile      = null;
let isDirty          = false;
let autoSaveTimer    = null;
let scratchTimer     = null;
let isFocusMode      = false;
let isPreviewVisible = false;
let showStats        = STORE.getBool('showStats', false);
let smartTypo        = STORE.getBool('smartTypo', true);
let typewriterOn     = STORE.getBool('typewriter', false);
let colWidth         = STORE.get('colWidth', 'normal');
let editorFontSize   = STORE.getNum('fontSize', 15);
let wordGoal         = STORE.getNum('wordGoal', 0);

const WIDTHS   = ['wide', 'normal', 'narrow'];
const FONT_MIN = 11;
const FONT_MAX = 24;

contentArea.classList.add('width-' + colWidth);
if (showStats) statsEl.classList.add('visible');
applyFontSize();
if (isMac) body.classList.add('mac');
if (isTauri) body.classList.add('tauri');

// ==========================
//  CodeMirror 6 setup
// ==========================

// Three theme families, each with a dark + light mode. Pequod is the
// original. Glauca and Try-Works are ports of the design systems of the
// same names (github.com/tiagojct/glauca, github.com/tiagojct/try-works);
// all values come straight from their source token JSONs.
const PALETTES = {
  pequod: {
    dark: {
      bg:           '#061826',
      bgElev:       '#0E2D44',
      bgDeep:       '#02101B',
      fg:           '#F7F3EE',
      fgDim:        '#C4BCAE',
      fgGhost:      '#8B8578',
      accent:       '#BD8C68',
      accentLight:  '#D4A882',
      accentDim:    '#8B6348',
      border:       '#0E2D44',
    },
    light: {
      bg:           '#F1E7D2',
      bgElev:       '#F8F0DD',
      bgDeep:       '#E2D5B7',
      fg:           '#1A2D3C',
      fgDim:        '#3F5566',
      fgGhost:      '#7A8B9A',
      accent:       '#8B6348',
      accentLight:  '#BD8C68',
      accentDim:    '#4F3825',
      border:       '#D7C9A8',
    },
  },
  glauca: {
    dark: {   // Profundum
      bg:           '#10161c',
      bgElev:       '#1f2932',
      bgDeep:       '#0b1218',
      fg:           '#e8eef2',
      fgDim:        '#93b7c9',
      fgGhost:      '#4d7391',
      accent:       '#3d97ff',
      accentLight:  '#6cb2ff',
      accentDim:    '#007aff',
      border:       '#2a3540',
    },
    light: {  // Pruina
      bg:           '#f0f4f6',
      bgElev:       '#ffffff',
      bgDeep:       '#e8eef2',
      fg:           '#16222a',
      fgDim:        '#55646d',
      fgGhost:      '#8c8c8c',
      accent:       '#0b62cf',
      accentLight:  '#007aff',
      accentDim:    '#084b96',
      border:       '#cdd7dc',
    },
  },
  tryworks: {
    dark: {   // Try-Fire
      bg:           '#12161b',
      bgElev:       '#232b32',
      bgDeep:       '#11151a',
      fg:           '#f1efe9',
      fgDim:        '#8fb6bd',
      fgGhost:      '#4d7680',
      accent:       '#c9651d',
      accentLight:  '#e0832a',
      accentDim:    '#9a4a16',
      border:       '#2c3640',
    },
    light: {  // True Lamp
      bg:           '#dee7e4',
      bgElev:       '#f2f7f4',
      bgDeep:       '#b4ccc9',
      fg:           '#18272b',
      fgDim:        '#52646a',
      fgGhost:      '#97a0a4',
      accent:       '#9e5017',
      accentLight:  '#b85f1c',
      accentDim:    '#7a3a10',
      border:       '#c4d2cd',
    },
  },
};

function makeHighlight(p) {
  return HighlightStyle.define([
    { tag: t.heading1,   color: p.accentLight, fontWeight: '700', fontSize: '1.6em' },
    { tag: t.heading2,   color: p.accentLight, fontWeight: '700', fontSize: '1.35em' },
    { tag: t.heading3,   color: p.accentLight, fontWeight: '700', fontSize: '1.15em' },
    { tag: t.heading4,   color: p.accentLight, fontWeight: '700', fontSize: '1.05em' },
    { tag: t.heading5,   color: p.accentLight, fontWeight: '700' },
    { tag: t.heading6,   color: p.accentLight, fontWeight: '700' },
    { tag: t.strong,     color: p.fg,          fontWeight: '700' },
    { tag: t.emphasis,   color: p.accentLight, fontStyle: 'italic' },
    { tag: t.monospace,  color: p.accentLight, class: 'tok-code' },
    { tag: t.link,       color: p.accent,      textDecoration: 'underline' },
    { tag: t.url,        color: p.accentDim },
    { tag: t.quote,      color: p.fgDim,       fontStyle: 'italic' },
    { tag: t.processingInstruction, color: p.fgGhost },
    { tag: t.contentSeparator,      color: p.fgGhost },
    { tag: t.list,       color: p.accent },
  ]);
}

function makeTheme(p, isDark) {
  return EditorView.theme({
    '&': {
      color: p.fg,
      backgroundColor: 'transparent',
      height: '100%',
      fontSize: 'var(--editor-fs)',
    },
    '&.cm-focused': { outline: 'none' },
    '.cm-content': {
      fontFamily: "'JetBrains Mono', 'SF Mono', monospace",
      padding: '24px 40px 80px',
      caretColor: p.fg,
      lineHeight: '1.8',
    },
    '.cm-scroller': {
      overflow: 'auto',
      fontFamily: "'JetBrains Mono', 'SF Mono', monospace",
      scrollbarWidth: 'none',
    },
    '.cm-scroller::-webkit-scrollbar': { display: 'none' },
    '.cm-line': { padding: '0' },
    '.cm-cursor, .cm-dropCursor': { borderLeftColor: p.fg, borderLeftWidth: '2px' },
    '.cm-selectionBackground, ::selection': { background: p.accent + ' !important' },
    '&.cm-focused .cm-selectionBackground': { background: p.accent + ' !important' },
    '.cm-placeholder': { color: p.fgGhost, fontStyle: 'italic', opacity: '0.5' },
    '.cm-panels': { backgroundColor: p.bgDeep, color: p.fg, borderBottom: `1px solid ${p.border}` },
    '.cm-panels.cm-panels-top': { borderBottom: `1px solid ${p.border}` },
    '.cm-search.cm-panel': { padding: '6px 10px', fontFamily: "'JetBrains Mono', 'SF Mono', monospace", fontSize: '12px' },
    '.cm-search input, .cm-search button, .cm-search label': { fontFamily: "'JetBrains Mono', 'SF Mono', monospace", fontSize: '12px' },
    '.cm-search input': {
      background: p.bg, color: p.fg, border: `1px solid ${p.border}`,
      padding: '2px 6px', borderRadius: '3px',
    },
    '.cm-search button': {
      background: p.bgElev, color: p.fg, border: 'none',
      padding: '2px 8px', borderRadius: '3px', cursor: 'pointer',
    },
    '.cm-search button:hover': { background: p.accent, color: p.bgDeep },
    '.cm-search [name=close]': { color: p.fgDim },
    '.cm-searchMatch': { backgroundColor: p.accent + '40' },
    '.cm-searchMatch.cm-searchMatch-selected': { backgroundColor: p.accentLight + '70' },
  }, { dark: isDark });
}

const fontSizeCompartment    = new Compartment();
const placeholderCompartment = new Compartment();
const themeCompartment       = new Compartment();
const highlightCompartment   = new Compartment();
const lineNumbersCompartment = new Compartment();

let themeMode  = STORE.get('themeMode', 'system');
let themeFamily = STORE.get('themeFamily', 'pequod');
if (!PALETTES[themeFamily]) themeFamily = 'pequod';
let activeTheme = resolveTheme(themeMode);
let lineNumbersOn = STORE.getBool('lineNumbers', false);

function resolveTheme(mode) {
  if (mode === 'dark' || mode === 'light') return mode;
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

function applyThemeAttr(theme) {
  document.documentElement.setAttribute('data-theme', theme);
  document.documentElement.setAttribute('data-palette', themeFamily);
}

applyThemeAttr(activeTheme);

function wrapSelection(left, right) {
  return (view) => {
    const sel = view.state.selection.main;
    if (sel.empty) {
      view.dispatch({
        changes: { from: sel.from, insert: left + right },
        selection: { anchor: sel.from + left.length },
      });
    } else {
      const text = view.state.sliceDoc(sel.from, sel.to);
      // Reselecting the FULL replacement (not just its inner text) is what
      // keeps repeated toggle presses clean instead of accumulating markers
      // each time — shared so both branches below can't drift apart.
      const replaceAndReselect = (newText) => {
        view.dispatch({
          changes: { from: sel.from, to: sel.to, insert: newText },
          selection: { anchor: sel.from, head: sel.from + newText.length },
        });
        return true;
      };
      // Italic ("*") toggling must not collide with bold's "**" markers —
      // naive prefix/suffix stripping would turn **bold** into *bold*
      // (bold → italic) instead of layering italic on top.
      if (left === '*' && right === '*') {
        if (text.length >= 6 && text.startsWith('***') && text.endsWith('***')) {
          return replaceAndReselect(text.slice(1, -1)); // ***bold*** -> **bold** (drop italic layer)
        }
        if (text.length >= 4 && text.startsWith('**') && text.endsWith('**')) {
          return replaceAndReselect(left + text + right); // **bold** -> ***bold*** (add italic layer)
        }
      }
      const stripped = text.startsWith(left) && text.endsWith(right) &&
        text.length >= left.length + right.length;
      if (stripped) {
        const inner = text.slice(left.length, text.length - right.length);
        view.dispatch({
          changes: { from: sel.from, to: sel.to, insert: inner },
          selection: { anchor: sel.from, head: sel.from + inner.length },
        });
      } else {
        view.dispatch({
          changes: { from: sel.from, to: sel.to, insert: left + text + right },
          selection: { anchor: sel.from + left.length, head: sel.to + left.length },
        });
      }
    }
    return true;
  };
}

const dimMark = Decoration.mark({ class: 'cm-dim-sentence' });
const frontmatterMark = Decoration.mark({ class: 'cm-frontmatter' });

const frontmatterPlugin = ViewPlugin.fromClass(class {
  constructor(view) { this.decorations = this.build(view); }
  update(update) {
    if (update.docChanged) this.decorations = this.build(update.view);
  }
  build(view) {
    const state = view.state;
    if (state.doc.lines < 3) return Decoration.none;
    const firstLine = state.doc.line(1);
    if (firstLine.text !== '---') return Decoration.none;
    for (let i = 2; i <= state.doc.lines; i++) {
      const line = state.doc.line(i);
      if (line.text === '---') {
        const builder = new RangeSetBuilder();
        builder.add(firstLine.from, line.to, frontmatterMark);
        return builder.finish();
      }
      if (i > 50) break;
    }
    return Decoration.none;
  }
}, { decorations: v => v.decorations });

// Signals a focus-mode on/off flip to the plugin below — the only update
// that isn't covered by docChanged/selectionSet.
const focusModeEffect = StateEffect.define();

const sentenceFocusPlugin = ViewPlugin.fromClass(class {
  constructor(view) { this.decorations = this.build(view); }
  update(update) {
    // Rebuilding on every view update (scroll, geometry, focus) is wasted
    // work — the dim ranges only move on edits, cursor moves, or toggle.
    const toggled = update.transactions.some(
      tr => tr.effects.some(e => e.is(focusModeEffect))
    );
    if (!isFocusMode) {
      if (toggled) this.decorations = Decoration.none;
      return;
    }
    if (toggled || update.docChanged || update.selectionSet) {
      this.decorations = this.build(update.view);
    }
  }
  build(view) {
    if (!isFocusMode) return Decoration.none;
    const state = view.state;
    const pos = state.selection.main.head;
    const docLen = state.doc.length;
    if (docLen === 0) return Decoration.none;

    const curLine = state.doc.lineAt(pos);
    let pStart = curLine.number, pEnd = curLine.number;
    while (pStart > 1 && state.doc.line(pStart - 1).text.trim() !== '') pStart--;
    while (pEnd < state.doc.lines && state.doc.line(pEnd + 1).text.trim() !== '') pEnd++;
    const pFrom = state.doc.line(pStart).from;
    const pTo   = state.doc.line(pEnd).to;
    const paraText = state.doc.sliceString(pFrom, pTo);
    const offsetInPara = pos - pFrom;

    const re = /[^.!?\n]*[.!?]+|\S[^.!?\n]*$/g;
    let m, activeFrom = -1, activeTo = -1;
    while ((m = re.exec(paraText)) !== null) {
      const sFrom = m.index, sTo = m.index + m[0].length;
      if (offsetInPara >= sFrom && offsetInPara <= sTo) {
        activeFrom = pFrom + sFrom;
        activeTo   = pFrom + sTo;
        break;
      }
    }
    if (activeFrom < 0) {
      activeFrom = pFrom;
      activeTo   = pTo;
    }

    const builder = new RangeSetBuilder();
    if (activeFrom > 0) builder.add(0, activeFrom, dimMark);
    if (activeTo < docLen) builder.add(activeTo, docLen, dimMark);
    return builder.finish();
  }
}, { decorations: v => v.decorations });

const smartTypographyHandler = EditorView.inputHandler.of((view, from, to, text) => {
  if (!smartTypo) return false;
  if (text === '"') {
    const prev = from > 0 ? view.state.sliceDoc(from - 1, from) : ' ';
    const rep = /\s|^|\(|\[|\{/.test(prev) ? '“' : '”';
    view.dispatch({ changes: { from, to, insert: rep }, selection: { anchor: from + 1 } });
    return true;
  }
  if (text === "'") {
    const prev = from > 0 ? view.state.sliceDoc(from - 1, from) : ' ';
    const rep = /\s|^|\(|\[|\{/.test(prev) ? '‘' : '’';
    view.dispatch({ changes: { from, to, insert: rep }, selection: { anchor: from + 1 } });
    return true;
  }
  if (text === '-' && from > 0 && view.state.sliceDoc(from - 1, from) === '-') {
    view.dispatch({ changes: { from: from - 1, to, insert: '—' }, selection: { anchor: from } });
    return true;
  }
  if (text === '.' && from >= 2 && view.state.sliceDoc(from - 2, from) === '..') {
    view.dispatch({ changes: { from: from - 2, to, insert: '…' }, selection: { anchor: from - 1 } });
    return true;
  }
  return false;
});

function toggleSmartTypo() {
  smartTypo = !smartTypo;
  STORE.setBool('smartTypo', smartTypo);
  flashStatus(`Smart typography: ${smartTypo ? 'on' : 'off'}`);
}

function toggleLineNumbers() {
  lineNumbersOn = !lineNumbersOn;
  STORE.setBool('lineNumbers', lineNumbersOn);
  view.dispatch({
    effects: lineNumbersCompartment.reconfigure(lineNumbersOn ? lineNumbers() : []),
  });
  flashStatus(`Line numbers: ${lineNumbersOn ? 'on' : 'off'}`);
}

function insertLink(view) {
  const sel = view.state.selection.main;
  if (sel.empty) {
    const ins = '[](url)';
    view.dispatch({
      changes: { from: sel.from, insert: ins },
      selection: { anchor: sel.from + 1 },
    });
  } else {
    const text = view.state.sliceDoc(sel.from, sel.to);
    const ins = `[${text}](url)`;
    const urlStart = sel.from + text.length + 3;
    view.dispatch({
      changes: { from: sel.from, to: sel.to, insert: ins },
      selection: { anchor: urlStart, head: urlStart + 3 },
    });
  }
  return true;
}

const continueListKey = {
  key: 'Enter',
  run: (view) => {
    const { state } = view;
    const sel = state.selection.main;
    if (!sel.empty) return false;
    const line = state.doc.lineAt(sel.head);
    if (sel.head !== line.to) return false;
    const text = line.text;

    let m = text.match(/^(\s*)([-*+])(\s+)(.*)$/);
    if (m) {
      const [, indent, marker, sp, content] = m;
      if (content === '') {
        view.dispatch({
          changes: { from: line.from, to: line.to, insert: indent },
          selection: { anchor: line.from + indent.length },
        });
        return true;
      }
      const insert = `\n${indent}${marker}${sp}`;
      view.dispatch({
        changes: { from: sel.head, insert },
        selection: { anchor: sel.head + insert.length },
      });
      return true;
    }

    m = text.match(/^(\s*)(\d+)([.)])(\s+)(.*)$/);
    if (m) {
      const [, indent, num, dot, sp, content] = m;
      if (content === '') {
        view.dispatch({
          changes: { from: line.from, to: line.to, insert: indent },
          selection: { anchor: line.from + indent.length },
        });
        return true;
      }
      const next = parseInt(num, 10) + 1;
      const insert = `\n${indent}${next}${dot}${sp}`;
      view.dispatch({
        changes: { from: sel.head, insert },
        selection: { anchor: sel.head + insert.length },
      });
      return true;
    }

    m = text.match(/^(\s*)>\s*(.*)$/);
    if (m) {
      const [, indent, content] = m;
      if (content === '') {
        view.dispatch({
          changes: { from: line.from, to: line.to, insert: indent },
          selection: { anchor: line.from + indent.length },
        });
        return true;
      }
      const insert = `\n${indent}> `;
      view.dispatch({
        changes: { from: sel.head, insert },
        selection: { anchor: sel.head + insert.length },
      });
      return true;
    }

    return false;
  },
};

function buildState(doc = '') {
  const p = PALETTES[themeFamily][activeTheme];
  return EditorState.create({
    doc,
    extensions: [
      history(),
      drawSelection(),
      indentOnInput(),
      bracketMatching(),
      markdown(),
      smartTypographyHandler,
      sentenceFocusPlugin,
      frontmatterPlugin,
      highlightCompartment.of(syntaxHighlighting(makeHighlight(p))),
      themeCompartment.of(makeTheme(p, activeTheme === 'dark')),
      lineNumbersCompartment.of(lineNumbersOn ? lineNumbers() : []),
      EditorView.lineWrapping,
      EditorView.contentAttributes.of({
        spellcheck: 'true',
        autocorrect: 'on',
        autocapitalize: 'sentences',
      }),
      search({ top: true }),
      placeholderCompartment.of(placeholder('The shapes loom before they take form…')),
      fontSizeCompartment.of(EditorView.theme({ '&': { fontSize: editorFontSize + 'px' } })),
      keymap.of([
        continueListKey,
        ...defaultKeymap,
        ...historyKeymap,
        ...searchKeymap,
        indentWithTab,
        { key: 'Mod-s',       run: () => { handleSave(); return true; } },
        { key: 'Mod-Shift-s', run: () => { handleSaveAs(); return true; } },
        { key: 'Mod-f',       run: (v) => { openSearchPanel(v); return true; } },
        { key: 'Mod-b',       run: wrapSelection('**', '**') },
        { key: 'Mod-i',       run: wrapSelection('*', '*') },
        { key: 'Mod-`',       run: wrapSelection('`', '`') },
        { key: 'Mod-k',       run: insertLink },
      ]),
      EditorView.updateListener.of((update) => {
        if (update.docChanged) markDirty();
        if (update.selectionSet || update.docChanged) {
          updateCursorPos();
          // Selection stats (word count of selection) track the selection —
          // but only reschedule on a plain cursor move (empty selection, no
          // doc change) if a selection just collapsed, so bare arrow-key
          // movement doesn't re-trigger an O(doc) stats scan every keypress.
          if (update.selectionSet && !update.docChanged) {
            const wasEmpty = update.startState.selection.main.empty;
            const isEmpty = update.state.selection.main.empty;
            if (!isEmpty || !wasEmpty) scheduleStats();
          }
        }
        // Typewriter mode keeps the cursor centered on edits AND on
        // cursor-only moves (arrows, clicks, Home/End) — not just typing.
        if (typewriterOn && (update.docChanged || update.selectionSet)) {
          scheduleTypewriterScroll(update.state.selection.main.head);
        }
      }),
    ],
  });
}

const view = new EditorView({
  state: buildState(''),
  parent: editorEl,
});

function getText() { return view.state.doc.toString(); }

function setText(text) {
  view.dispatch({
    changes: { from: 0, to: view.state.doc.length, insert: text },
  });
}

// ==========================
//  Font size
// ==========================

function applyFontSize() {
  document.documentElement.style.setProperty('--editor-fs', editorFontSize + 'px');
}

function changeFontSize(delta) {
  editorFontSize = Math.min(FONT_MAX, Math.max(FONT_MIN, editorFontSize + delta));
  STORE.set('fontSize', editorFontSize);
  applyFontSize();
  view.dispatch({
    effects: fontSizeCompartment.reconfigure(
      EditorView.theme({ '&': { fontSize: editorFontSize + 'px' } })
    ),
  });
}

// ==========================
//  Column width
// ==========================

function cycleWidth() {
  const idx = WIDTHS.indexOf(colWidth);
  colWidth = WIDTHS[(idx + 1) % WIDTHS.length];
  STORE.set('colWidth', colWidth);
  contentArea.className = contentArea.className.replace(/width-\w+/g, '');
  contentArea.classList.add('width-' + colWidth);
}

// ==========================
//  Theme
// ==========================

function applyTheme(next) {
  activeTheme = next;
  applyThemeAttr(next);
  const p = PALETTES[themeFamily][next];
  view.dispatch({
    effects: [
      themeCompartment.reconfigure(makeTheme(p, next === 'dark')),
      highlightCompartment.reconfigure(syntaxHighlighting(makeHighlight(p))),
    ],
  });
}

function cycleTheme() {
  const order = ['system', 'light', 'dark'];
  const next = order[(order.indexOf(themeMode) + 1) % order.length];
  themeMode = next;
  STORE.set('themeMode', next);
  applyTheme(resolveTheme(next));
  flashStatus(`Theme: ${next}`);
}

const FAMILY_LABELS = { pequod: 'Pequod', glauca: 'Glauca', tryworks: 'Try-Works' };

function setThemeFamily(family) {
  if (!PALETTES[family]) return;
  if (family === themeFamily) {
    // Re-clicking the active radio item: muda already auto-unchecked it on
    // click, so re-sync the checkmark even though nothing else changes.
    ipcSyncThemeMenu(family);
    return;
  }
  themeFamily = family;
  STORE.set('themeFamily', family);
  applyTheme(resolveTheme(themeMode));
  ipcSyncThemeMenu(family);
  flashStatus(`Theme: ${FAMILY_LABELS[family]}`);
}

window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
  if (themeMode === 'system') applyTheme(resolveTheme('system'));
});

// ==========================
//  Stats
// ==========================

function countWords(text) {
  // Native regex pass — JS \s already covers Unicode space separators
  // (em space, ideographic space, etc), unlike a hand-rolled ASCII scan.
  const words = text.match(/\S+/g);
  return words ? words.length : 0;
}

function updateStats() {
  const sel = view.state.selection.main;
  if (!sel.empty) {
    // Selection stats take over while a selection exists.
    const text = view.state.sliceDoc(sel.from, sel.to);
    const words = countWords(text);
    const fromLine = view.state.doc.lineAt(sel.from);
    const toLine = view.state.doc.lineAt(sel.to);
    // A selection ending exactly at a line's start includes none of that
    // line's own text (just the previous line's trailing newline) — don't
    // count it, or a selection of two full lines reads as three.
    const toLineNum = (toLine.number > fromLine.number && sel.to === toLine.from)
      ? toLine.number - 1
      : toLine.number;
    const lines = toLineNum - fromLine.number + 1;
    statWords.textContent = `${words} w`;
    statChars.textContent = `${text.length} c`;
    statLines.textContent = `${lines} ln (sel)`;
    statRead.textContent = '';
    return;
  }
  const text = getText();
  const words = countWords(text);
  statWords.textContent = wordGoal > 0
    ? `${words} / ${wordGoal} w (${Math.min(100, Math.round(words / wordGoal * 100))}%)`
    : `${words} w`;
  statChars.textContent = `${text.length} c`;
  statLines.textContent = `${view.state.doc.lines} ln`;
  statRead.textContent = words > 0 ? `~${Math.max(1, Math.ceil(words / 200))} min` : '';
}

// Stats are O(doc) — never compute them per keystroke, and never when the
// stats bar is hidden.
let statsTimer = null;
function scheduleStats() {
  if (!showStats) return;
  clearTimeout(statsTimer);
  statsTimer = setTimeout(updateStats, 250);
}

let previewTimer = null;
function schedulePreview() {
  if (!isPreviewVisible) return;
  clearTimeout(previewTimer);
  previewTimer = setTimeout(updatePreview, 150);
}

const WORD_GOALS = [0, 250, 500, 750, 1000, 2000, 5000];

function cycleWordGoal() {
  const idx = WORD_GOALS.indexOf(wordGoal);
  wordGoal = WORD_GOALS[(idx + 1) % WORD_GOALS.length];
  STORE.set('wordGoal', wordGoal);
  updateStats();
  flashStatus(wordGoal === 0 ? 'Word goal: off' : `Word goal: ${wordGoal}`);
}

function updateCursorPos() {
  const head = view.state.selection.main.head;
  const line = view.state.doc.lineAt(head);
  cursorPosEl.textContent = `Ln ${line.number}, Col ${head - line.from + 1}`;
}

// ==========================
//  Outline palette (Cmd+P jump to heading)
// ==========================

const paletteEl    = document.getElementById('palette');
const paletteInput = document.getElementById('palette-input');
const paletteList  = document.getElementById('palette-list');
let paletteHeadings = [];
let paletteIdx      = 0;

function extractHeadings(state) {
  const out = [];
  syntaxTree(state).iterate({
    enter(node) {
      const m = node.name.match(/^ATXHeading(\d)$/);
      if (m) {
        const level = parseInt(m[1], 10);
        const line  = state.doc.lineAt(node.from);
        const text  = line.text.replace(/^#+\s*/, '').trim();
        out.push({ level, text, from: line.from, line: line.number });
      } else if (node.name === 'SetextHeading1' || node.name === 'SetextHeading2') {
        const level = node.name === 'SetextHeading1' ? 1 : 2;
        const line  = state.doc.lineAt(node.from);
        out.push({ level, text: line.text.trim(), from: line.from, line: line.number });
      }
    },
  });
  return out;
}

function filteredHeadings() {
  const q = paletteInput.value.toLowerCase().trim();
  if (!q) return paletteHeadings;
  return paletteHeadings.filter(h => h.text.toLowerCase().includes(q));
}

function escHtml(s) {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function renderPalette() {
  const list = filteredHeadings();
  if (list.length === 0) {
    paletteList.innerHTML = '';
    return;
  }
  if (paletteIdx >= list.length) paletteIdx = list.length - 1;
  if (paletteIdx < 0) paletteIdx = 0;
  paletteList.innerHTML = list.map((h, i) =>
    `<li class="palette-item lvl-${h.level} ${i === paletteIdx ? 'sel' : ''}" data-i="${i}">
       <span class="palette-level">H${h.level}</span>
       <span class="palette-text">${escHtml(h.text || '(empty)')}</span>
     </li>`
  ).join('');
  const sel = paletteList.querySelector('.palette-item.sel');
  if (sel) sel.scrollIntoView({ block: 'nearest' });
}

function openPalette() {
  paletteHeadings = extractHeadings(view.state);
  paletteIdx = 0;
  paletteInput.value = '';
  paletteEl.classList.remove('hidden');
  renderPalette();
  paletteInput.focus();
}

function closePalette() {
  paletteEl.classList.add('hidden');
  view.focus();
}

// ==========================
//  About modal
// ==========================

const aboutEl       = document.getElementById('about');
const aboutIcon     = document.getElementById('about-icon');
const aboutVersion  = document.getElementById('about-version');
const aboutTech     = document.getElementById('about-tech');
const aboutExample  = document.getElementById('about-example');

function initAbout() {
  aboutIcon.src = new URL('./icon.png', import.meta.url).href;
  aboutIcon.onerror = () => { aboutIcon.style.display = 'none'; };
  // Single source of truth: the version Tauri was built with (or, on web,
  // the version this build was published from).
  getVersion()
    .then((v) => { aboutVersion.textContent = `Version ${v}`; })
    .catch(() => { aboutVersion.textContent = ''; });
  if (!isTauri) aboutTech.textContent = 'MIT licensed. Built with CodeMirror 6.';
}

function openAbout() {
  aboutEl.classList.remove('hidden');
}
function closeAbout() {
  aboutEl.classList.add('hidden');
  view.focus();
}

// ==========================
//  Welcome modal (first launch)
// ==========================

const welcomeEl           = document.getElementById('welcome');
const welcomeLedeEl       = document.getElementById('welcome-lede');
const welcomeInstrEl      = document.getElementById('welcome-instructions');
const welcomeGotItBtn     = document.getElementById('welcome-got-it');

function welcomeInstructionsForOS() {
  const p = (navigator.platform || '').toLowerCase();
  const ua = (navigator.userAgent || '').toLowerCase();
  if (/mac/.test(p) || /mac/.test(ua)) {
    return `
      <ol>
        <li>In <strong>Finder</strong>, right-click any <code>.md</code> file.</li>
        <li>Choose <strong>Get Info</strong> (<code>⌘ I</code>).</li>
        <li>Under <strong>Open with</strong>, pick <strong>Loomings</strong>.</li>
        <li>Click <strong>Change All…</strong> and confirm.</li>
      </ol>`;
  }
  if (/win/.test(p) || /win/.test(ua)) {
    return `
      <ol>
        <li>In <strong>Explorer</strong>, right-click any <code>.md</code> file.</li>
        <li>Choose <strong>Open with → Choose another app</strong>.</li>
        <li>Pick <strong>Loomings</strong>, tick <strong>Always use this app</strong>, then <strong>OK</strong>.</li>
      </ol>`;
  }
  return `
    <ol>
      <li>In your file manager, right-click any <code>.md</code> file.</li>
      <li>Pick <strong>Open With → Other Application</strong> (or <strong>Properties → Open With</strong>).</li>
      <li>Choose <strong>Loomings</strong> and mark it as the default.</li>
    </ol>`;
}

function showWelcomeIfFirstLaunch() {
  if (STORE.getBool('welcomeSeen', false)) return;
  // If the app was launched by opening a file (Finder / argv), skip the
  // welcome — the user already discovered the file-association story.
  if (currentFile) {
    STORE.setBool('welcomeSeen', true);
    return;
  }
  if (isTauri) {
    welcomeInstrEl.innerHTML = welcomeInstructionsForOS();
  } else {
    // File-association setup is meaningless on the web build — there's no
    // OS integration to configure, just the in-page toolbar.
    welcomeLedeEl.textContent = 'Use the toolbar above to open, save, and export files.';
    welcomeInstrEl.innerHTML = `
      <ol>
        <li>Chrome/Edge: files open and save in place, just like a native app.</li>
        <li>Firefox/Safari: opening uses a file picker and saving downloads a copy (no File System Access API yet).</li>
      </ol>`;
  }
  welcomeEl.classList.remove('hidden');
}
function closeWelcome() {
  welcomeEl.classList.add('hidden');
  STORE.setBool('welcomeSeen', true);
  view.focus();
}
welcomeGotItBtn.addEventListener('click', closeWelcome);
welcomeEl.addEventListener('click', (e) => {
  if (e.target === welcomeEl) closeWelcome();
});

aboutEl.addEventListener('click', (e) => {
  if (e.target === aboutEl) closeAbout();
});
aboutEl.querySelectorAll('a[data-url]').forEach(a => {
  a.addEventListener('click', (e) => {
    e.preventDefault();
    openUrl(a.dataset.url).catch(() => {});
  });
});
aboutExample.addEventListener('click', (e) => {
  e.preventDefault();
  closeAbout();
  // Tauri: fire-and-forget, Rust emits file-opened and the existing
  // listener picks it up. Web: the payload comes straight back.
  ipcOpenExample().then((payload) => { if (payload) loadFile(payload); }).catch(() => {});
});

// ==========================
//  Update banner
// ==========================

const updateBannerEl  = document.getElementById('update-banner');
const updateMessageEl = document.getElementById('update-message');
const updateLinkEl    = document.getElementById('update-link');
const updateDismissEl = document.getElementById('update-dismiss');

let latestUpdateUrl = null;

function showUpdateBanner(info) {
  updateMessageEl.textContent = `Loomings ${info.version} is available.`;
  latestUpdateUrl = info.url;
  updateBannerEl.classList.remove('hidden');
}
function hideUpdateBanner() {
  updateBannerEl.classList.add('hidden');
}
updateLinkEl.addEventListener('click', (e) => {
  e.preventDefault();
  if (latestUpdateUrl) openUrl(latestUpdateUrl).catch(() => {});
});
updateDismissEl.addEventListener('click', hideUpdateBanner);

let updateCheckInFlight = false;

async function runUpdateCheck(manual = false) {
  if (updateCheckInFlight) {
    if (manual) flashStatus('Already checking…');
    return;
  }
  updateCheckInFlight = true;
  if (manual) flashStatus('Checking for updates…');
  try {
    const info = await ipcCheckForUpdate();
    if (info) {
      showUpdateBanner(info);
      if (manual) flashStatus(`Loomings ${info.version} is available.`);
    } else if (manual) {
      flashStatus('You’re up to date.');
    }
  } catch (_) {
    if (manual) flashStatus('Update check failed.');
  } finally {
    updateCheckInFlight = false;
  }
}

function jumpToHeading(idx) {
  const list = filteredHeadings();
  const h = list[idx];
  if (!h) return;
  view.dispatch({
    selection: { anchor: h.from },
    effects: EditorView.scrollIntoView(h.from, { y: 'start' }),
  });
  closePalette();
}

paletteInput.addEventListener('input', () => { paletteIdx = 0; renderPalette(); });
paletteInput.addEventListener('keydown', (e) => {
  if (e.key === 'Escape')    { e.preventDefault(); closePalette(); return; }
  if (e.key === 'Enter')     { e.preventDefault(); jumpToHeading(paletteIdx); return; }
  if (e.key === 'ArrowDown') {
    e.preventDefault();
    paletteIdx = Math.min(paletteIdx + 1, filteredHeadings().length - 1);
    renderPalette();
    return;
  }
  if (e.key === 'ArrowUp') {
    e.preventDefault();
    paletteIdx = Math.max(paletteIdx - 1, 0);
    renderPalette();
    return;
  }
});
paletteList.addEventListener('click', (e) => {
  const li = e.target.closest('.palette-item');
  if (li) jumpToHeading(parseInt(li.dataset.i, 10));
});
paletteEl.addEventListener('click', (e) => {
  if (e.target === paletteEl) closePalette();
});

function toggleStats() {
  showStats = !showStats;
  STORE.setBool('showStats', showStats);
  statsEl.classList.toggle('visible', showStats);
  if (showStats) updateStats(); // stats were not maintained while hidden
}

// ==========================
//  Dirty / Auto-save / Scratch
// ==========================

function markDirty() {
  if (!isDirty) { isDirty = true; dirtyEl.classList.remove('hidden'); }
  resetAutoSave();
  resetScratchSave();
  scheduleStats();
  schedulePreview();
}

// NOTE: deliberately does NOT clear the scratch buffer — markClean fires on
// every 2s autosave and deleting scratch.json each time is pointless churn.
// read_scratch (Rust) drops a scratch that matches the file on disk, so a
// stale scratch never produces a bogus recovery prompt. Scratch is cleared
// explicitly on New / close / recovery-decline.
function markClean() {
  isDirty = false;
  dirtyEl.classList.add('hidden');
}

function resetAutoSave() {
  clearTimeout(autoSaveTimer);
  autoSaveTimer = setTimeout(() => {
    if (isDirty && currentFile) doSave(currentFile, getText());
  }, 2000);
}

// Bumped every time the buffer is repointed at a different document (New,
// Open, external reload, Save As). doSave/writeScratch capture it before an
// await and check it after — if it moved on, a slow save/scratch-write that
// finishes late knows its result now describes an abandoned buffer and must
// not touch lastSavedContent/lastScratchContent/isDirty on the buffer that
// replaced it.
let docGeneration = 0;

let lastScratchContent = null;
// Tracks the most recent in-flight scratch write so quit can wait for it —
// otherwise a write racing the close sequence could land after clear_scratch
// and leave an orphan scratch file (see doSave / request-close).
let scratchSaveInFlight = null;

function writeScratch(text, forFile) {
  if (text === lastScratchContent) return;
  lastScratchContent = text;
  const gen = docGeneration;
  // Chain behind any write already in flight — write_atomic's temp filename
  // isn't unique per call, so two concurrent scratch writes (a slow one from
  // resetScratchSave's timer overlapping one from doSave) can race each
  // other's rename, same as doSave's saveInFlight guards against for the
  // real file.
  const previous = scratchSaveInFlight;
  scratchSaveInFlight = (async () => {
    if (previous) await previous;
    await ipcSaveScratch(text, forFile);
    // A discard that ran while this write was still in flight can't have
    // cleared content this write hadn't landed yet — re-clear now so a
    // stalled write can't resurrect an abandoned buffer's scratch file.
    if (gen !== docGeneration) await ipcClearScratch();
  })();
}

// Drop the scratch buffer for the document we're about to leave behind
// (New, opening a different file, or reloading from disk) — otherwise it
// keeps describing an abandoned buffer and a later crash offers to
// "recover" content the user already discarded. Bumping docGeneration
// first means even a write that's still in flight past the bounded wait
// below will re-clear itself via writeScratch's own check once it lands.
async function discardScratch() {
  clearTimeout(scratchTimer);
  docGeneration++;
  await Promise.race([scratchSaveInFlight, new Promise((r) => setTimeout(r, 2000))]);
  lastScratchContent = null;
  await ipcClearScratch();
}

function resetScratchSave() {
  clearTimeout(scratchTimer);
  scratchTimer = setTimeout(() => {
    if (!isDirty) return;
    writeScratch(getText(), currentFile);
  }, 800);
}

// Last content we wrote to disk ourselves — lets handleExternalChange tell
// our own write's watcher echo apart from a real external edit.
let lastSavedContent = null;

// Serializes doSave calls — the 2s autosave timer and an explicit Cmd+S can
// fire close enough together that two ipcSaveFile calls for the same path
// would overlap; write_atomic's temp filename isn't unique per-call, so
// concurrent writes can race each other's rename. Awaiting any save already
// in flight before starting a new one keeps writes to one at a time.
let saveInFlight = null;

async function doSave(path, content) {
  const gen = docGeneration;
  if (saveInFlight) await saveInFlight;
  const save = (async () => {
    try {
      await ipcSaveFile(path, content);
      // The buffer moved on (New/Open/reload/Save As) while this write was
      // in flight — the write itself is harmless (it landed on the path it
      // targeted), but its result no longer describes the current buffer,
      // so don't let it stomp fresher state.
      if (gen !== docGeneration) return;
      lastSavedContent = content;
      // Keep scratch in sync with what's now safely on disk. Without this, a
      // scratch write from before this save can go stale — read_scratch's
      // dedup (scratch content vs. disk content) only catches up on the next
      // edit, so a crash between this save and the next keystroke would offer
      // to "recover" content older than what's already saved.
      writeScratch(content, path);
      markClean();
      flashStatus('Saved');
    }
    catch (err) { flashStatus('Save failed: ' + (err?.message || err)); }
  })();
  saveInFlight = save;
  await save;
  if (saveInFlight === save) saveInFlight = null;
}

function flashStatus(msg) {
  statusApp.textContent = msg;
  clearTimeout(statusApp._timeout);
  statusApp._timeout = setTimeout(refreshStatusBar, 2000);
}

// ipcWatchFile has no push equivalent on web (a true no-op there); on
// Tauri, surface a denied watch once so the user knows reload-on-
// external-change is dead for this file.
function onWatchFail(err) { flashStatus('File watcher failed: ' + (err?.message || err)); }

function basename(p) {
  if (!p) return '';
  const parts = p.split(/[\\/]/);
  return parts[parts.length - 1];
}

// Window-title name: basename minus any extension we open (not just .md).
function displayName(p) {
  return basename(p).replace(/\.(md|markdown|mdown|mkd|qmd|rmd|txt)$/i, '');
}

function refreshStatusBar() {
  statusApp.textContent = 'Loomings';
  if (currentFile) {
    statusFile.textContent = '— ' + basename(currentFile);
    statusFile.classList.remove('hidden');
  } else {
    statusFile.classList.add('hidden');
  }
}

async function handleSave() {
  if (currentFile) await doSave(currentFile, getText());
  else            await handleSaveAs();
}

async function handleSaveAs() {
  try {
    const text = getText();
    const path = await ipcSaveFileAs(text);
    if (path) {
      docGeneration++; // any save still in flight for the old path/target must not stomp this
      currentFile = path;
      lastSavedContent = text;
      // Re-point scratch at the new path so it stays in sync with disk —
      // the old scratch (current_file: null, untitled) is superseded.
      lastScratchContent = null;
      writeScratch(text, path);
      await ipcAddRecent(path);
      refreshRecents();
      await ipcWatchFile(path, onWatchFail);
      ipcSetTitle(displayName(path));
      markClean(); refreshStatusBar();
    }
  } catch (err) { flashStatus('Save failed: ' + (err?.message || err)); }
}

async function exportHtml() {
  const p = PALETTES[themeFamily][activeTheme];
  const title = currentFile ? displayName(currentFile) : 'Untitled';
  const rendered = renderMarkdown(getText());
  const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${escHtml(title)}</title>
<style>
  body { max-width: 680px; margin: 0 auto; padding: 48px 24px;
         font-family: Georgia, 'Times New Roman', serif; font-size: 17px; line-height: 1.8;
         background: ${p.bg}; color: ${p.fg}; }
  h1, h2, h3, h4, h5, h6 { color: ${p.accentLight}; line-height: 1.3; }
  a { color: ${p.accent}; }
  code { font-family: ui-monospace, 'SF Mono', Menlo, monospace; font-size: 0.9em;
         background: ${p.bgDeep}; color: ${p.accentLight}; padding: 2px 6px; border-radius: 3px; }
  pre { background: ${p.bgDeep}; border: 1px solid ${p.border}; padding: 16px;
        border-radius: 4px; overflow-x: auto; }
  pre code { background: none; padding: 0; color: ${p.fgDim}; }
  blockquote { border-left: 3px solid ${p.accent}; padding-left: 16px;
               color: ${p.fgDim}; margin-left: 0; font-style: italic; }
  hr { border: none; border-top: 1px solid ${p.border}; margin: 2em 0; }
  img { max-width: 100%; }
  @media print { body { background: #fff; color: #000; } }
</style>
</head>
<body>
${rendered}
</body>
</html>
`;
  try {
    const path = await ipcExportHtml(html, title + '.html');
    if (path) flashStatus('Exported ' + basename(path));
  } catch (err) {
    flashStatus('Export failed: ' + (err?.message || err));
  }
}

async function confirmDiscard(prompt) {
  if (!isDirty) return true;
  const message = prompt + '\n\nUnsaved changes will be lost.';
  try {
    return await ask(message, { title: 'Loomings', kind: 'warning' });
  } catch (_) {
    return false;
  }
}

async function fileNew() {
  if (isDirty) {
    const proceed = await confirmDiscard('Discard the current document?');
    if (!proceed) return;
  }
  clearTimeout(autoSaveTimer);
  await discardScratch();
  setText('');
  currentFile = null;
  lastSavedContent = null;
  ipcUnwatchFile();
  ipcSetTitle(null);
  markClean(); updateStats(); updatePreview(); refreshStatusBar();
  view.focus();
}

// ==========================
//  Focus / Preview
// ==========================

function toggleFocusMode() {
  isFocusMode = !isFocusMode;
  body.classList.toggle('focus-mode', isFocusMode);
  view.dispatch({ effects: focusModeEffect.of(isFocusMode) });
}

// Coalesces rapid docChanged/selectionSet updates (fast typing, paste) into
// one scroll per frame instead of one requestAnimationFrame + dispatch per
// keystroke — dispatching inside an update cycle isn't allowed, so this
// still has to defer, but only once per frame no matter how many updates
// land in it.
let typewriterFrame = null;
function scheduleTypewriterScroll(head) {
  if (typewriterFrame !== null) cancelAnimationFrame(typewriterFrame);
  typewriterFrame = requestAnimationFrame(() => {
    typewriterFrame = null;
    view.dispatch({ effects: EditorView.scrollIntoView(head, { y: 'center' }) });
  });
}

function toggleTypewriter() {
  typewriterOn = !typewriterOn;
  STORE.setBool('typewriter', typewriterOn);
  if (typewriterOn) {
    view.dispatch({
      effects: EditorView.scrollIntoView(view.state.selection.main.head, { y: 'center' }),
    });
  } else if (typewriterFrame !== null) {
    // A recenter queued by the last keystroke/move before disabling would
    // otherwise still fire on the next frame and jump the view once more.
    cancelAnimationFrame(typewriterFrame);
    typewriterFrame = null;
  }
  flashStatus(`Typewriter scrolling: ${typewriterOn ? 'on' : 'off'}`);
}

function togglePreview() {
  isPreviewVisible = !isPreviewVisible;
  if (isPreviewVisible) {
    preview.classList.remove('hidden');
    preview.classList.add('visible');
    editorEl.classList.add('hidden');
    updatePreview();
  } else {
    preview.classList.remove('visible');
    preview.classList.add('hidden');
    editorEl.classList.remove('hidden');
    view.focus();
  }
}

// ==========================
//  Markdown preview (with URL sanitization)
// ==========================

const md = new MarkdownIt({
  html: false,
  linkify: true,
  typographer: true,
  breaks: false,
});

const SAFE_URL = /^(https?:|mailto:|#|\/|\.\/|\.\.\/)/i;
const defaultLinkOpen = md.renderer.rules.link_open || function (tokens, idx, opts, _, self) {
  return self.renderToken(tokens, idx, opts);
};
md.renderer.rules.link_open = function (tokens, idx, opts, env, self) {
  const token = tokens[idx];
  const hrefIdx = token.attrIndex('href');
  if (hrefIdx >= 0) {
    const href = token.attrs[hrefIdx][1];
    if (!SAFE_URL.test(href)) token.attrs[hrefIdx][1] = '#';
  }
  token.attrSet('rel', 'noopener noreferrer');
  return defaultLinkOpen(tokens, idx, opts, env, self);
};
const defaultImage = md.renderer.rules.image;
md.renderer.rules.image = function (tokens, idx, opts, env, self) {
  const token = tokens[idx];
  const srcIdx = token.attrIndex('src');
  if (srcIdx >= 0) {
    const src = token.attrs[srcIdx][1];
    if (!SAFE_URL.test(src) && !/^data:image\//i.test(src)) {
      token.attrs[srcIdx][1] = '#';
    }
  }
  return defaultImage(tokens, idx, opts, env, self);
};

function renderMarkdown(text) {
  return md.render(text);
}

function updatePreview() {
  if (isPreviewVisible) preview.innerHTML = renderMarkdown(getText());
}

// Links in the rendered preview must open in the system browser, not
// navigate the webview (Tauri blocks external navigation anyway).
preview.addEventListener('click', (e) => {
  const a = e.target.closest('a[href]');
  if (!a) return;
  const href = a.getAttribute('href');
  // Only http(s)/mailto need routing to the system browser/mail client;
  // in-page anchors (#heading) and relative links keep default webview
  // navigation so they still work.
  if (/^(https?:|mailto:)/i.test(href)) {
    e.preventDefault();
    openUrl(href).catch(() => {});
  }
});

// ==========================
//  Global keyboard shortcuts (outside editor)
// ==========================

document.addEventListener('keydown', (e) => {
  const mod = e.metaKey || e.ctrlKey;

  if (e.key === 'Escape') {
    if (!welcomeEl.classList.contains('hidden')) { closeWelcome();    return; }
    if (!aboutEl.classList.contains('hidden'))   { closeAbout();      return; }
    if (isPreviewVisible)                        { togglePreview();   return; }
    if (isFocusMode)                             { toggleFocusMode(); return; }
    return;
  }

  if (mod && (e.key === '=' || e.key === '+')) { e.preventDefault(); changeFontSize(1);  return; }
  if (mod && e.key === '-')                     { e.preventDefault(); changeFontSize(-1); return; }

  // toUpperCase: with caps lock on, shift+d reports key 'd'.
  const k = e.key.length === 1 ? e.key.toUpperCase() : e.key;
  if (mod && e.shiftKey && k === 'D') { e.preventDefault(); toggleFocusMode(); return; }
  if (mod && e.shiftKey && k === 'P') { e.preventDefault(); togglePreview();   return; }
  if (mod && e.shiftKey && k === 'L') { e.preventDefault(); toggleStats();     return; }
  if (mod && e.shiftKey && k === 'W') { e.preventDefault(); cycleWidth();      return; }
  if (mod && e.shiftKey && k === 'T') { e.preventDefault(); cycleTheme();      return; }
  if (mod && e.shiftKey && k === 'G') { e.preventDefault(); cycleWordGoal();   return; }
  if (mod && !e.shiftKey && k === 'P') { e.preventDefault(); openPalette();    return; }
});

// ==========================
//  IPC listeners
// ==========================

async function loadFile(payload) {
  if (isDirty) {
    const proceed = await confirmDiscard('Open new file?');
    if (!proceed) return;
  }
  await discardScratch(); // the buffer we're replacing is no longer relevant to recover
  setText(payload.content);
  lastSavedContent = null;
  if (!payload.path) {
    // Untitled buffer with content (the bundled example) — no autosave
    // target, no watcher, no recents. Saving goes through Save As.
    currentFile = null;
    ipcUnwatchFile();
    ipcSetTitle('Moby-Dick');
  } else {
    currentFile = payload.path;
    ipcSetTitle(displayName(payload.path));
    ipcAddRecent(payload.path);
    refreshRecents();
    await ipcWatchFile(payload.path, onWatchFail);
  }
  markClean(); updateStats(); updatePreview(); refreshStatusBar();
  view.focus();
}

async function handleExternalChange(payload) {
  if (!currentFile || payload.path !== currentFile) return;
  if (payload.content === getText()) return;
  // Watcher echo of our own save (the user kept typing during the 400ms
  // watcher debounce, so buffer ≠ disk) — not an external edit.
  if (payload.content === lastSavedContent) return;
  const message = isDirty
    ? 'File changed on disk:\n' + basename(currentFile) +
      '\n\nYour buffer has unsaved changes. Reload from disk and lose them?'
    : 'File changed on disk:\n' + basename(currentFile) + '\n\nReload?';
  const reload = await ask(message, { title: 'Loomings', kind: 'warning' });
  if (!reload) return;
  // Let any of our own in-flight save finish first — otherwise it can
  // physically write to this path after we've reloaded, leaving disk out
  // of sync with what's now in the buffer. Bounded so a stalled write
  // can't block the reload indefinitely.
  await Promise.race([saveInFlight, new Promise((r) => setTimeout(r, 2000))]);
  await discardScratch(); // the pre-reload buffer being discarded shouldn't come back on recovery
  setText(payload.content);
  lastSavedContent = payload.content;
  markClean();
  updateStats(); updatePreview();
}

async function registerListeners() {
  await Promise.all([
    listen('file-opened',          (e) => loadFile(e.payload)),
    listen('file-changed-on-disk', (e) => handleExternalChange(e.payload)),
    listen('file-new',             ()  => fileNew()),
    listen('request-save',         ()  => handleSave()),
    listen('request-save-as',      ()  => handleSaveAs()),
    listen('toggle-focus',         ()  => toggleFocusMode()),
    listen('toggle-preview',       ()  => togglePreview()),
    listen('toggle-stats',         ()  => toggleStats()),
    listen('toggle-width',         ()  => cycleWidth()),
    listen('toggle-theme',         ()  => cycleTheme()),
    listen('cycle-goal',           ()  => cycleWordGoal()),
    listen('toggle-typo',          ()  => toggleSmartTypo()),
    listen('toggle-line-numbers',  ()  => toggleLineNumbers()),
    listen('toggle-typewriter',    ()  => toggleTypewriter()),
    listen('set-theme-family',     (e) => setThemeFamily(e.payload)),
    listen('menu-rebuilt',         ()  => ipcSyncThemeMenu(themeFamily)),
    listen('request-export-html',  ()  => exportHtml()),
    listen('open-palette',         ()  => openPalette()),
    listen('open-about',           ()  => openAbout()),
    listen('manual-update-check',  ()  => runUpdateCheck(true)),
    listen('open-url',             (e) => { if (e.payload) openUrl(e.payload).catch(() => {}); }),
    listen('font-size',            (e) => changeFontSize(e.payload)),
    listen('request-close',     async () => {
      // Named files autosave — flush the pending save instead of scaring
      // the user with a "changes will be lost" prompt that isn't true.
      if (isDirty && currentFile) {
        clearTimeout(autoSaveTimer);
        await doSave(currentFile, getText());
      }
      if (isDirty) {
        // Untitled buffer, or the flush above failed.
        const proceed = await confirmDiscard('Quit Loomings?');
        // No cancel-side IPC: the Rust handler always intercepts the close
        // and waits for confirm_quit. Doing nothing leaves the window open.
        if (!proceed) return;
      }
      clearTimeout(autoSaveTimer);
      await discardScratch();
      await ipcConfirmQuit();
    }),
  ]);
}

// ==========================
//  Window drag (titlebar) + drag-and-drop to open
// ==========================

const titlebar = document.getElementById('titlebar');
initTitlebarDrag(titlebar); // no-op on web — no window to drag in a browser tab

// Both platforms' onFile payload is {path, content}, same shape loadFile
// already takes — Tauri's is unused internally (its own drop-open flow
// goes through the existing file-opened listener instead) but kept for a
// uniform call site.
initDragDrop(loadFile, (err) => flashStatus('Open failed: ' + (err?.message || err)));

// ==========================
//  Web toolbar (no native menu bar on the web build)
// ==========================

async function openFile() {
  // loadFile itself runs the dirty-check on the result; the file picker
  // showing regardless of current buffer state matches how the native
  // Open dialog already behaves.
  const payload = await ipcOpenFile();
  if (payload) await loadFile(payload);
}

const tbRecent = document.getElementById('tb-recent');

async function refreshRecents() {
  if (isTauri || !getRecents) return; // native "Open Recent" menu covers Tauri
  const recents = await getRecents();
  if (!recents.length) {
    tbRecent.classList.add('hidden');
    tbRecent.innerHTML = '';
    return;
  }
  tbRecent.innerHTML = '<option value="" disabled selected>Recent…</option>' +
    recents.map((r, i) => `<option value="${i}">${escHtml(r.name)}</option>`).join('');
  tbRecent.classList.remove('hidden');
}

tbRecent?.addEventListener('change', async () => {
  const idx = parseInt(tbRecent.value, 10);
  tbRecent.value = '';
  const recents = await getRecents();
  const entry = recents[idx];
  if (!entry) return;
  const payload = await openRecent(entry);
  if (payload) await loadFile(payload);
  else flashStatus('Could not reopen — permission declined');
  refreshRecents();
});

const THEME_FAMILY_ORDER = ['pequod', 'glauca', 'tryworks'];
function cycleThemeFamily() {
  const next = THEME_FAMILY_ORDER[(THEME_FAMILY_ORDER.indexOf(themeFamily) + 1) % THEME_FAMILY_ORDER.length];
  setThemeFamily(next);
}

document.getElementById('tb-new')?.addEventListener('click', fileNew);
document.getElementById('tb-open')?.addEventListener('click', openFile);
document.getElementById('tb-save')?.addEventListener('click', handleSave);
document.getElementById('tb-export')?.addEventListener('click', exportHtml);
document.getElementById('tb-theme')?.addEventListener('click', cycleThemeFamily);
document.getElementById('tb-about')?.addEventListener('click', openAbout);

// A dirty buffer left open in a closed tab is otherwise silently lost —
// blunter than the native flush-and-ask flow (generic browser dialog, no
// custom copy, can't await the async scratch-flush first) but real insurance.
window.addEventListener('beforeunload', (e) => {
  if (isDirty) e.preventDefault();
});

// ==========================
//  Init + scratch recovery
// ==========================

(async () => {
  await registerListeners();
  initAbout();
  ipcSyncThemeMenu(themeFamily);
  refreshRecents();

  // Drain the launch-file cache BEFORE scratch recovery — if the user
  // double-clicked an .md file in Finder, that's the document they want,
  // not "do you want to recover yesterday's draft?".
  const launch = await ipcTakeLaunchFile();
  if (launch && launch.content !== undefined) {
    await loadFile(launch);
  } else {
    const scratch = await ipcReadScratch();
    if (scratch && scratch.content && scratch.content.length > 0) {
      const recover = await ask(
        'Unsaved draft found from previous session. Recover it?\n\n' +
        (scratch.current_file ? 'File: ' + basename(scratch.current_file) : '(untitled)'),
        { title: 'Loomings', kind: 'info' }
      );
      if (recover) {
        setText(scratch.content);
        currentFile = scratch.current_file || null;
        if (currentFile) {
          ipcSetTitle(displayName(currentFile));
          await ipcWatchFile(currentFile, onWatchFail);
        }
        markDirty();
      } else {
        await ipcClearScratch();
      }
    }
  }

  updateStats(); updateCursorPos(); refreshStatusBar();
  view.focus();
  ipcSetTitle(currentFile ? displayName(currentFile) : null);

  // Tell Rust the frontend is alive — subsequent macOS RunEvent::Opened
  // events (warm "Open With") will go straight to the file-opened listener.
  await ipcFrontendReady();

  setTimeout(() => runUpdateCheck(false), 3000);
  setTimeout(showWelcomeIfFirstLaunch, 600);
})();
