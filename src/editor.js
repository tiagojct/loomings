// ========================================
// Loomings — Editor (CodeMirror 6, browser only)
// ========================================

import { EditorState, Compartment, RangeSetBuilder, StateEffect } from '@codemirror/state';
import { EditorView, keymap, drawSelection, lineNumbers, placeholder, ViewPlugin, Decoration } from '@codemirror/view';
import { history, defaultKeymap, historyKeymap, indentWithTab } from '@codemirror/commands';
import { markdown } from '@codemirror/lang-markdown';
import { HighlightStyle, syntaxHighlighting, indentOnInput, bracketMatching, syntaxTree } from '@codemirror/language';
import { search, searchKeymap, openSearchPanel } from '@codemirror/search';
import { tags as t } from '@lezer/highlight';
import MarkdownIt from 'markdown-it';
import { PALETTES, FAMILY_ORDER, DEFAULT_FAMILY, roles, cssVars } from './palettes.js';
import {
  hasFileSystemAccess, getVersion, openUrl, ask, setTitle,
  saveFile, saveFileAs, openFile as pickFile, openExample, downloadHtml,
  addRecent, getRecents, openRecent,
  saveScratch, readScratch, clearScratch,
  initDragDrop, forgetFile,
} from './browser.js';
import { shareUrl, payloadFromUrl, decodeDoc } from './share.js';
import { LESSONS, lessonBySlug } from './lessons.js';

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
let showStats        = STORE.getBool('showStats', false);
let smartTypo        = STORE.getBool('smartTypo', true);
let typewriterOn     = STORE.getBool('typewriter', false);
let colWidth         = STORE.get('colWidth', 'normal');
let editorFontSize   = STORE.getNum('fontSize', 15);
let wordGoal         = STORE.getNum('wordGoal', 0);

const WIDTHS   = ['wide', 'normal', 'narrow'];
const VIEW_MODES = ['editor', 'split', 'preview'];
let viewMode = STORE.get('viewMode', 'editor');
if (!VIEW_MODES.includes(viewMode)) viewMode = 'editor';
// Below this width two panes are unreadable, so split falls back to the
// editor and the Split button hides (see effectiveViewMode / style.css).
const narrowMq = window.matchMedia('(max-width: 760px)');
const FONT_MIN = 11;
const FONT_MAX = 24;

contentArea.classList.add('width-' + colWidth);
if (showStats) statsEl.classList.add('visible');
applyFontSize();
if (isMac) body.classList.add('mac');

// ==========================
//  CodeMirror 6 setup
// ==========================

function makeHighlight(p) {
  return HighlightStyle.define([
    { tag: t.heading1,   color: p.heading,  fontWeight: '700', fontSize: '1.6em' },
    { tag: t.heading2,   color: p.heading,  fontWeight: '700', fontSize: '1.35em' },
    { tag: t.heading3,   color: p.heading,  fontWeight: '700', fontSize: '1.15em' },
    { tag: t.heading4,   color: p.heading,  fontWeight: '700', fontSize: '1.05em' },
    { tag: t.heading5,   color: p.heading,  fontWeight: '700' },
    { tag: t.heading6,   color: p.heading,  fontWeight: '700' },
    { tag: t.strong,     color: p.fg,       fontWeight: '700' },
    { tag: t.emphasis,   color: p.emphasis, fontStyle: 'italic' },
    { tag: t.monospace,  color: p.code,     class: 'tok-code' },
    { tag: t.link,       color: p.accent,      textDecoration: 'underline' },
    { tag: t.url,        color: p.accentDim },
    { tag: t.quote,      color: p.fgDim,       fontStyle: 'italic' },
    { tag: t.processingInstruction, color: p.fgGhost },
    { tag: t.contentSeparator,      color: p.fgGhost },
    { tag: t.list,       color: p.marker },
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
let themeFamily = STORE.get('themeFamily', DEFAULT_FAMILY);
if (!PALETTES[themeFamily]) themeFamily = DEFAULT_FAMILY;
if (!['system', 'light', 'dark'].includes(themeMode)) themeMode = 'system';
let activeTheme = resolveTheme(themeMode);
let lineNumbersOn = STORE.getBool('lineNumbers', false);

function resolveTheme(mode) {
  if (mode === 'dark' || mode === 'light') return mode;
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

// style.css only carries Pequod as a pre-script fallback; every family's
// variables are written here from palettes.js, the single source.
function applyThemeAttr(theme) {
  const root = document.documentElement;
  root.setAttribute('data-theme', theme);
  root.setAttribute('data-palette', themeFamily);
  for (const [name, value] of Object.entries(cssVars(themeFamily, theme))) {
    root.style.setProperty(name, value);
  }
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
  const p = roles(themeFamily, activeTheme);
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
  const p = roles(themeFamily, next);
  view.dispatch({
    effects: [
      themeCompartment.reconfigure(makeTheme(p, next === 'dark')),
      highlightCompartment.reconfigure(syntaxHighlighting(makeHighlight(p))),
    ],
  });
  renderThemeMenu();
}

const MODE_ORDER = ['system', 'light', 'dark'];
const MODE_LABELS = { system: 'System', light: 'Light', dark: 'Dark' };

function setThemeMode(mode) {
  if (!MODE_ORDER.includes(mode)) return;
  themeMode = mode;
  STORE.set('themeMode', mode);
  applyTheme(resolveTheme(mode));
  flashStatus(`Theme: ${MODE_LABELS[mode]}`);
}

function cycleTheme() {
  setThemeMode(MODE_ORDER[(MODE_ORDER.indexOf(themeMode) + 1) % MODE_ORDER.length]);
}

function setThemeFamily(family) {
  if (!PALETTES[family] || family === themeFamily) return;
  themeFamily = family;
  STORE.set('themeFamily', family);
  applyTheme(resolveTheme(themeMode));
  flashStatus(`Theme: ${PALETTES[family].label}`);
}

// ==========================
//  Theme menu (toolbar)
// ==========================

const themeMenuEl     = document.getElementById('theme-menu');
const themeMenuBtn    = document.getElementById('tb-theme');
const themeFamiliesEl = document.getElementById('theme-families');
const themeModesEl    = document.getElementById('theme-modes');

function renderThemeMenu() {
  if (!themeMenuEl) return;
  themeFamiliesEl.innerHTML = FAMILY_ORDER.map((f) => {
    const fam = PALETTES[f];
    const sw = fam[activeTheme];
    return `<button type="button" class="tb-menu-item ${f === themeFamily ? 'on' : ''}" role="menuitemradio"
              aria-checked="${f === themeFamily}" data-family="${f}">
      <span class="swatch" style="background:${sw.bg};border-color:${sw.border}"><i style="background:${sw.accent}"></i></span>
      <span class="tb-menu-label">${escHtml(fam.label)}</span>
      <span class="tb-menu-hint">${escHtml(fam.modes[activeTheme])}</span>
    </button>`;
  }).join('');
  themeModesEl.innerHTML = MODE_ORDER.map((m) =>
    `<button type="button" class="tb-menu-item ${m === themeMode ? 'on' : ''}" role="menuitemradio"
       aria-checked="${m === themeMode}" data-mode="${m}">
      <span class="tb-menu-label">${MODE_LABELS[m]}</span>
    </button>`
  ).join('');
}

// A toolbar button that opens a popover menu. One open at a time; any
// click outside, Escape, or picking an item closes it.
const openMenus = new Set();
function attachMenu(btn, menuEl, { onOpen, onPick } = {}) {
  if (!btn || !menuEl) return { close() {} };
  const open = () => { closeAllMenus(); onOpen?.(); menuEl.classList.remove('hidden'); btn.setAttribute('aria-expanded', 'true'); openMenus.add(close); };
  const close = () => { menuEl.classList.add('hidden'); btn.setAttribute('aria-expanded', 'false'); openMenus.delete(close); };
  btn.addEventListener('click', (e) => { e.stopPropagation(); menuEl.classList.contains('hidden') ? open() : close(); });
  menuEl.addEventListener('click', (e) => {
    e.stopPropagation();
    const item = e.target.closest('.tb-menu-item');
    if (!item) return;
    close();
    onPick?.(item);
  });
  return { close };
}
function closeAllMenus() { for (const close of [...openMenus]) close(); }
document.addEventListener('click', closeAllMenus);

attachMenu(themeMenuBtn, themeMenuEl, {
  onOpen: renderThemeMenu,
  onPick: (item) => {
    if (item.dataset.family) setThemeFamily(item.dataset.family);
    if (item.dataset.mode) setThemeMode(item.dataset.mode);
  },
});

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
  if (!previewShown()) return;
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
const aboutExample  = document.getElementById('about-example');

function initAbout() {
  aboutIcon.src = new URL('./icon.png', import.meta.url).href;
  aboutIcon.onerror = () => { aboutIcon.style.display = 'none'; };
  // The version this build was published from (package.json).
  getVersion()
    .then((v) => { aboutVersion.textContent = `Version ${v}`; })
    .catch(() => { aboutVersion.textContent = ''; });
}

function openAbout() {
  aboutEl.classList.remove('hidden');
}
function closeAbout() {
  aboutEl.classList.add('hidden');
  view.focus();
}

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
  openExample().then((payload) => { if (payload) loadFile({ ...payload, title: 'Moby-Dick' }); }).catch(() => {});
});

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

// NOTE: deliberately does NOT touch the scratch buffer — markClean fires on
// every 2s autosave. doSave clears scratch itself once disk has the content;
// New / Open / recovery-decline clear it explicitly.
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
  // Chain behind any write already in flight so two overlapping scratch
  // writes can't land out of order (same idea as doSave's saveInFlight).
  const previous = scratchSaveInFlight;
  scratchSaveInFlight = (async () => {
    if (previous) await previous;
    await saveScratch(text, forFile);
    // A discard that ran while this write was still in flight can't have
    // cleared content this write hadn't landed yet — re-clear now so a
    // stalled write can't resurrect an abandoned buffer's scratch record.
    if (gen !== docGeneration) await clearScratch();
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
  await clearScratch();
}

function resetScratchSave() {
  clearTimeout(scratchTimer);
  scratchTimer = setTimeout(() => {
    if (!isDirty) return;
    writeScratch(getText(), currentFile);
  }, 800);
}

// Last content we wrote to disk ourselves.
let lastSavedContent = null;

// Serializes doSave calls — the 2s autosave timer and an explicit Cmd+S can
// fire close enough together that two writes to the same handle would
// overlap. Awaiting any save already in flight keeps writes one at a time.
let saveInFlight = null;

async function doSave(path, content) {
  const gen = docGeneration;
  if (saveInFlight) await saveInFlight;
  const save = (async () => {
    try {
      await saveFile(path, content);
      // The buffer moved on (New/Open/reload/Save As) while this write was
      // in flight — the write itself is harmless (it landed on the path it
      // targeted), but its result no longer describes the current buffer,
      // so don't let it stomp fresher state.
      if (gen !== docGeneration) return;
      lastSavedContent = content;
      // Disk has this content now — a scratch copy of it would only produce
      // a bogus "recover draft?" prompt on the next visit.
      lastScratchContent = content;
      clearScratchAfterInFlight();
      markClean();
      flashStatus('Saved');
    }
    catch (err) { flashStatus('Save failed: ' + (err?.message || err)); }
  })();
  saveInFlight = save;
  await save;
  if (saveInFlight === save) saveInFlight = null;
}

async function clearScratchAfterInFlight() {
  await scratchSaveInFlight;
  await clearScratch();
}

function flashStatus(msg) {
  statusApp.textContent = msg;
  clearTimeout(statusApp._timeout);
  statusApp._timeout = setTimeout(refreshStatusBar, 2000);
}

function basename(p) {
  if (!p) return '';
  const parts = p.split(/[\\/]/);
  return parts[parts.length - 1];
}

// Window-title name: basename minus any extension we open (not just .md).
function displayName(p) {
  return basename(p).replace(/\.(md|markdown|mdown|mkd|qmd|rmd|txt)$/i, '');
}

// Filename offered by Save As: the current file, else the first heading.
function suggestedFilename() {
  if (currentFile) return basename(currentFile);
  const m = getText().match(/^#\s+(.+)$/m);
  const slug = m ? m[1].trim().toLowerCase().replace(/[^\p{L}\p{N}]+/gu, '-').replace(/^-|-$/g, '') : '';
  return (slug || 'untitled') + '.md';
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
    const path = await saveFileAs(text, suggestedFilename());
    if (path) {
      docGeneration++; // any save still in flight for the old path/target must not stomp this
      currentFile = path;
      lastSavedContent = text;
      lastScratchContent = text;
      clearScratchAfterInFlight();
      await addRecent(path);
      refreshRecents();
      setTitle(displayName(path));
      markClean(); refreshStatusBar();
    } else if (!hasFileSystemAccess) {
      // Firefox/Safari: the "save" was a download, so the buffer is still
      // only in this tab — say so instead of pretending it's on disk.
      flashStatus('Downloaded a copy — this browser can’t save in place');
    }
  } catch (err) { flashStatus('Save failed: ' + (err?.message || err)); }
}

async function exportHtml() {
  const p = roles(themeFamily, activeTheme);
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
  h1, h2, h3, h4, h5, h6 { color: ${p.heading}; line-height: 1.3; }
  a { color: ${p.accent}; }
  em { color: ${p.emphasis}; }
  code { font-family: ui-monospace, 'SF Mono', Menlo, monospace; font-size: 0.9em;
         background: ${p.bgDeep}; color: ${p.code}; padding: 2px 6px; border-radius: 3px; }
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
    const path = await downloadHtml(html, title + '.html');
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
  setTitle(null);
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

// ==========================
//  View modes: editor / split / preview
// ==========================

function effectiveViewMode() {
  return (viewMode === 'split' && narrowMq.matches) ? 'editor' : viewMode;
}
function previewShown() { return effectiveViewMode() !== 'editor'; }

function applyViewMode() {
  const mode = effectiveViewMode();
  for (const m of VIEW_MODES) body.classList.toggle('view-' + m, m === mode);
  editorEl.classList.toggle('hidden', mode === 'preview');
  preview.classList.toggle('hidden', mode === 'editor');
  document.querySelectorAll('#web-toolbar [data-view]').forEach((b) => {
    b.setAttribute('aria-pressed', String(b.dataset.view === mode));
  });
  if (mode !== 'editor') updatePreview();
  if (mode !== 'preview') view.requestMeasure();
  if (mode === 'split') syncPreviewToEditor();
}

function setViewMode(mode) {
  if (!VIEW_MODES.includes(mode)) return;
  viewMode = mode;
  STORE.set('viewMode', mode);
  applyViewMode();
  if (effectiveViewMode() !== 'preview') view.focus();
}

// ⌘⇧P: editor ⇄ preview (from split, goes to preview). ⌘\: editor ⇄ split.
function togglePreview() { setViewMode(effectiveViewMode() === 'preview' ? 'editor' : 'preview'); }
function toggleSplit()   { setViewMode(viewMode === 'split' ? 'editor' : 'split'); }

narrowMq.addEventListener('change', applyViewMode);

// ==========================
//  Scroll sync (split mode)
// ==========================
// The preview's block elements carry data-line (source line, 0-based, from
// markdown-it's token.map). Editor → preview maps the top visible editor
// line onto the two nearest marked blocks and interpolates; preview →
// editor picks the first block at or below the preview's scrollTop. A
// short-lived lock stops the two handlers from feeding each other.

let syncLock = { source: null, until: 0 };
function lockSync(source) { syncLock = { source, until: performance.now() + 120 }; }
function syncLockedBy(other) { return syncLock.source === other && performance.now() < syncLock.until; }

function previewBlocks() {
  return Array.from(preview.querySelectorAll('[data-line]')).map((el) => ({
    el, line: parseInt(el.dataset.line, 10), top: el.offsetTop,
  })).filter((b) => !Number.isNaN(b.line));
}

function syncPreviewToEditor() {
  if (effectiveViewMode() !== 'split' || syncLockedBy('preview')) return;
  const scroller = view.scrollDOM;
  const blocks = previewBlocks();
  if (!blocks.length) return;
  const maxScroll = preview.scrollHeight - preview.clientHeight;
  let target;
  if (scroller.scrollTop + scroller.clientHeight >= scroller.scrollHeight - 2) {
    target = maxScroll; // pinned to the bottom stays pinned to the bottom
  } else {
    const block = view.lineBlockAtHeight(scroller.scrollTop);
    const lineNo = view.state.doc.lineAt(block.from).number - 1;
    // Fraction of the way through the top line, so the mapping is continuous.
    const within = block.height > 0 ? (scroller.scrollTop - block.top) / block.height : 0;
    const srcLine = lineNo + Math.max(0, Math.min(1, within));
    let a = blocks[0], b = null;
    for (const blk of blocks) {
      if (blk.line <= srcLine) a = blk; else { b = blk; break; }
    }
    if (!b) {
      target = a.top;
    } else {
      const span = b.line - a.line;
      const frac = span > 0 ? (srcLine - a.line) / span : 0;
      target = a.top + frac * (b.top - a.top);
    }
  }
  lockSync('editor');
  preview.scrollTop = Math.max(0, Math.min(maxScroll, target));
}

function syncEditorToPreview() {
  if (effectiveViewMode() !== 'split' || syncLockedBy('editor')) return;
  const blocks = previewBlocks();
  if (!blocks.length) return;
  const top = preview.scrollTop;
  let a = blocks[0], b = null;
  for (const blk of blocks) {
    if (blk.top <= top) a = blk; else { b = blk; break; }
  }
  let srcLine = a.line;
  if (b && b.top > a.top) srcLine = a.line + ((top - a.top) / (b.top - a.top)) * (b.line - a.line);
  const lineNo = Math.max(1, Math.min(view.state.doc.lines, Math.floor(srcLine) + 1));
  const line = view.state.doc.line(lineNo);
  lockSync('preview');
  const block = view.lineBlockAt(line.from);
  const frac = srcLine - Math.floor(srcLine);
  view.scrollDOM.scrollTop = block.top + frac * block.height;
}

view.scrollDOM.addEventListener('scroll', () => {
  if (effectiveViewMode() === 'split') requestAnimationFrame(syncPreviewToEditor);
}, { passive: true });
preview.addEventListener('scroll', () => {
  if (effectiveViewMode() === 'split') requestAnimationFrame(syncEditorToPreview);
}, { passive: true });

// ==========================
//  Markdown preview (with URL sanitization)
// ==========================

const md = new MarkdownIt({
  html: false,
  linkify: true,
  typographer: true,
  breaks: false,
});

// Stamp every block token that knows its source range with data-line so
// the scroll sync (and, later, click-to-locate) can map preview ⇄ source.
md.core.ruler.push('source_lines', (state) => {
  for (const token of state.tokens) {
    if (token.map && token.nesting !== -1 && !token.hidden) {
      token.attrSet('data-line', String(token.map[0]));
    }
  }
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
  if (!previewShown()) return;
  preview.innerHTML = renderMarkdown(getText());
  if (effectiveViewMode() === 'split') syncPreviewToEditor();
}

// Print / PDF: the print stylesheet shows only the rendered preview, so make
// sure it is current even when the user is in editor-only mode.
function printPreview() {
  const wasShown = previewShown();
  preview.innerHTML = renderMarkdown(getText());
  if (!wasShown) preview.classList.remove('hidden');
  const cleanup = () => { if (!wasShown) preview.classList.add('hidden'); window.removeEventListener('afterprint', cleanup); };
  window.addEventListener('afterprint', cleanup);
  window.print();
}

// Links in the rendered preview open in a new tab rather than navigating
// the editor away from an unsaved buffer.
preview.addEventListener('click', (e) => {
  const a = e.target.closest('a[href]');
  if (!a) return;
  const href = a.getAttribute('href');
  // Only http(s)/mailto need routing; in-page anchors (#heading) keep
  // default navigation so they still work.
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
    if (openMenus.size) { closeAllMenus(); return; }
    if (!cheatsheetEl.classList.contains('hidden')) { toggleCheatsheet(false); return; }
    if (!aboutEl.classList.contains('hidden'))   { closeAbout();      return; }
    if (effectiveViewMode() === 'preview')       { setViewMode('editor'); return; }
    if (isFocusMode)                             { toggleFocusMode(); return; }
    return;
  }

  if (mod && (e.key === '=' || e.key === '+')) { e.preventDefault(); changeFontSize(1);  return; }
  if (mod && e.key === '-')                     { e.preventDefault(); changeFontSize(-1); return; }

  // toUpperCase: with caps lock on, shift+d reports key 'd'.
  const k = e.key.length === 1 ? e.key.toUpperCase() : e.key;
  if (mod && e.shiftKey && k === 'D') { e.preventDefault(); toggleFocusMode(); return; }
  if (mod && e.shiftKey && k === 'P') { e.preventDefault(); togglePreview();   return; }
  if (mod && !e.shiftKey && e.key === '\\') { e.preventDefault(); toggleSplit();  return; }
  if (mod && e.key === '?')                   { e.preventDefault(); toggleCheatsheet(); return; }
  if (mod && e.shiftKey && k === 'L') { e.preventDefault(); toggleStats();     return; }
  if (mod && e.shiftKey && k === 'W') { e.preventDefault(); cycleWidth();      return; }
  if (mod && e.shiftKey && k === 'T') { e.preventDefault(); cycleTheme();      return; }
  if (mod && e.shiftKey && k === 'G') { e.preventDefault(); cycleWordGoal();   return; }
  if (mod && !e.shiftKey && k === 'P') { e.preventDefault(); openPalette();    return; }
});

// ==========================
//  Loading documents
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
    // Untitled buffer with content (example, lesson, share link) — no
    // autosave target, no recents, and no file handle left behind that a
    // later Save could overwrite. Saving goes through Save As.
    currentFile = null;
    forgetFile();
    setTitle(payload.title || null);
  } else {
    currentFile = payload.path;
    setTitle(displayName(payload.path));
    addRecent(payload.path);
    refreshRecents();
  }
  markClean(); updateStats(); updatePreview(); refreshStatusBar();
  view.focus();
}

// ==========================
//  Drag-and-drop to open
// ==========================

initDragDrop(loadFile, (err) => flashStatus('Open failed: ' + (err?.message || err)));

// ==========================
//  Share links (document in the URL fragment)
// ==========================

function firstHeading(text) {
  const m = text.match(/^#\s+(.+)$/m);
  return m ? m[1].trim() : null;
}

async function copyShareLink() {
  const text = getText();
  if (!text.trim()) { flashStatus('Nothing to share yet'); return; }
  try {
    const url = await shareUrl(text, location.href);
    const kb = Math.max(1, Math.round(url.length / 1024));
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(url);
      flashStatus(`Link copied (${kb} KB) — the whole document travels in it`);
    } else {
      window.prompt('Copy this link:', url);
    }
  } catch (err) {
    flashStatus('Could not build link: ' + (err?.message || err));
  }
}

async function loadSharedPayload(payload) {
  let content;
  try { content = await decodeDoc(payload); }
  catch (err) { flashStatus('Could not open shared link: ' + (err?.message || err)); return false; }
  await loadFile({ path: '', content, title: firstHeading(content) || 'Shared document' });
  return true;
}

// ==========================
//  Lessons (bundled, ?lesson=slug)
// ==========================

async function openLesson(slug) {
  const lesson = lessonBySlug(slug);
  if (!lesson) { flashStatus('No lesson called ' + slug); return false; }
  await loadFile({ path: '', content: lesson.content, title: lesson.title });
  // Lessons are written to be read source-beside-result.
  if (!narrowMq.matches) setViewMode('split');
  return true;
}

// A document named in the URL wins over scratch recovery, the same way an
// explicitly opened file always did. The URL is then cleaned so a reload
// goes back through the normal (scratch-recovering) boot.
async function loadFromLocation() {
  const share = payloadFromUrl(location.href);
  const lesson = new URLSearchParams(location.search).get('lesson');
  if (!share && !lesson) return false;
  window.history.replaceState(null, '', location.pathname);
  if (share) return loadSharedPayload(share);
  return openLesson(lesson);
}

window.addEventListener('hashchange', () => {
  const share = payloadFromUrl(location.href);
  if (!share) return;
  window.history.replaceState(null, '', location.pathname);
  loadSharedPayload(share);
});

// ==========================
//  Cheatsheet drawer
// ==========================

const cheatsheetEl = document.getElementById('cheatsheet');
function toggleCheatsheet(force) {
  const show = force ?? cheatsheetEl.classList.contains('hidden');
  cheatsheetEl.classList.toggle('hidden', !show);
  if (!show) view.focus();
}
document.getElementById('cheatsheet-close')?.addEventListener('click', () => toggleCheatsheet(false));

// ==========================
//  Toolbar
// ==========================

async function openFile() {
  // loadFile itself runs the dirty-check on the result.
  const payload = await pickFile();
  if (payload) await loadFile(payload);
}

const tbRecent = document.getElementById('tb-recent');

async function refreshRecents() {
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

document.getElementById('tb-new')?.addEventListener('click', fileNew);
document.getElementById('tb-open')?.addEventListener('click', openFile);
document.getElementById('tb-save')?.addEventListener('click', handleSave);
attachMenu(document.getElementById('tb-export'), document.getElementById('export-menu'), {
  onPick: (item) => {
    if (item.dataset.action === 'html')  exportHtml();
    if (item.dataset.action === 'print') printPreview();
    if (item.dataset.action === 'share') copyShareLink();
  },
});

const learnMenuEl = document.getElementById('learn-menu');
const learnLessonsEl = document.getElementById('learn-lessons');
attachMenu(document.getElementById('tb-learn'), learnMenuEl, {
  onOpen: () => {
    learnLessonsEl.innerHTML = LESSONS.map((l, i) =>
      `<button type="button" class="tb-menu-item" role="menuitem" data-lesson="${escHtml(l.slug)}">
         <span class="tb-menu-num">${i + 1}</span><span class="tb-menu-label">${escHtml(l.title)}</span>
       </button>`
    ).join('');
  },
  onPick: (item) => {
    if (item.dataset.lesson) openLesson(item.dataset.lesson);
    if (item.dataset.action === 'cheatsheet') toggleCheatsheet();
    if (item.dataset.action === 'example') openExample().then((p) => { if (p) loadFile({ ...p, title: 'Moby-Dick' }); });
  },
});
document.querySelectorAll('#web-toolbar [data-view]').forEach((b) => {
  b.addEventListener('click', () => setViewMode(b.dataset.view));
});
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

async function offerScratchRecovery() {
  const scratch = await readScratch();
  if (!scratch || !scratch.content || scratch.content.length === 0) return;
  const recover = await ask(
    'Unsaved draft found from previous session. Recover it?\n\n' +
    (scratch.current_file ? 'File: ' + basename(scratch.current_file) : '(untitled)')
  );
  if (recover) {
    setText(scratch.content);
    // The file handle can't be restored without a picker, so the recovered
    // buffer is untitled — Save goes through Save As. The name still shows.
    currentFile = null;
    if (scratch.current_file) flashStatus('Recovered draft of ' + basename(scratch.current_file));
    markDirty();
  } else {
    await clearScratch();
  }
}

(async () => {
  initAbout();
  refreshRecents();
  applyViewMode();
  if (!(await loadFromLocation())) await offerScratchRecovery();
  updateStats(); updateCursorPos(); refreshStatusBar();
  view.focus();
})();
