// ========================================
// Loomings — Editor (Tauri v2 + CodeMirror 6)
// ========================================

import { EditorState, Compartment, RangeSetBuilder } from '@codemirror/state';
import { EditorView, keymap, drawSelection, highlightActiveLine, placeholder, ViewPlugin, Decoration } from '@codemirror/view';
import { history, defaultKeymap, historyKeymap, indentWithTab } from '@codemirror/commands';
import { markdown } from '@codemirror/lang-markdown';
import { HighlightStyle, syntaxHighlighting, indentOnInput, bracketMatching, syntaxTree } from '@codemirror/language';
import { search, searchKeymap, openSearchPanel } from '@codemirror/search';
import { tags as t } from '@lezer/highlight';
import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
import { getCurrentWindow } from '@tauri-apps/api/window';
import { ask } from '@tauri-apps/plugin-dialog';
import MarkdownIt from 'markdown-it';

const isMac = /Mac/i.test(navigator.platform) || /Mac/i.test(navigator.userAgent);

const editorEl    = document.getElementById('editor');
const preview     = document.getElementById('preview');
const contentArea = document.getElementById('content-area');
const dirtyEl     = document.getElementById('dirty');
const statsEl     = document.getElementById('stats');
const statWords   = document.getElementById('stat-words');
const statChars   = document.getElementById('stat-chars');
const statLines   = document.getElementById('stat-lines');
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

// ==========================
//  CodeMirror 6 setup
// ==========================

const PALETTES = {
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
    '.cm-activeLine': { backgroundColor: 'transparent' },
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

let themeMode  = STORE.get('themeMode', 'system');
let activeTheme = resolveTheme(themeMode);

function resolveTheme(mode) {
  if (mode === 'dark' || mode === 'light') return mode;
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

function applyThemeAttr(theme) {
  document.documentElement.setAttribute('data-theme', theme);
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
      const stripped = text.startsWith(left) && text.endsWith(right) && text.length >= left.length + right.length;
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

const sentenceFocusPlugin = ViewPlugin.fromClass(class {
  constructor(view) { this.decorations = this.build(view); }
  update(update) {
    this.decorations = this.build(update.view);
  }
  build(view) {
    if (!body.classList.contains('focus-mode')) return Decoration.none;
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
  const p = PALETTES[activeTheme];
  return EditorState.create({
    doc,
    extensions: [
      history(),
      drawSelection(),
      indentOnInput(),
      bracketMatching(),
      highlightActiveLine(),
      markdown(),
      smartTypographyHandler,
      sentenceFocusPlugin,
      frontmatterPlugin,
      highlightCompartment.of(syntaxHighlighting(makeHighlight(p))),
      themeCompartment.of(makeTheme(p, activeTheme === 'dark')),
      EditorView.lineWrapping,
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
        if (update.selectionSet || update.docChanged) updateCursorPos();
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
//  IPC helpers
// ==========================

async function ipcSetTitle(title)         { try { await invoke('set_title', { title }); } catch (_) {} }
async function ipcSaveFile(path, content) { return invoke('save_file', { path, content }); }
async function ipcSaveFileAs(content)     { return invoke('save_file_as', { content }); }
async function ipcAddRecent(filePath)     { try { await invoke('add_recent_file', { filePath }); } catch (_) {} }
async function ipcSaveScratch(content, currentFile) {
  try { await invoke('save_scratch', { content, currentFile }); } catch (_) {}
}
async function ipcReadScratch()  { try { return await invoke('read_scratch'); } catch (_) { return null; } }
async function ipcClearScratch() { try { await invoke('clear_scratch'); } catch (_) {} }
async function ipcConfirmQuit()  { return invoke('confirm_quit'); }
async function ipcCancelQuitRequest() { try { await invoke('cancel_quit_request'); } catch (_) {} }
async function ipcWatchFile(path) { try { await invoke('watch_file', { path }); } catch (_) {} }
async function ipcUnwatchFile()  { try { await invoke('unwatch_file'); } catch (_) {} }

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
  const p = PALETTES[next];
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

window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
  if (themeMode === 'system') applyTheme(resolveTheme('system'));
});

// ==========================
//  Stats
// ==========================

function updateStats() {
  const text = getText();
  const words = text.trim() ? text.trim().split(/\s+/).length : 0;
  statWords.textContent = wordGoal > 0
    ? `${words} / ${wordGoal} w (${Math.min(100, Math.round(words / wordGoal * 100))}%)`
    : `${words} w`;
  statChars.textContent = `${text.length} c`;
  statLines.textContent = `${view.state.doc.lines} ln`;
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

const APP_VERSION = '0.2.3';

function initAbout() {
  aboutIcon.src = new URL('./icon.png', import.meta.url).href;
  aboutIcon.onerror = () => { aboutIcon.style.display = 'none'; };
  aboutVersion.textContent = `Version ${APP_VERSION}`;
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
    window.open(a.dataset.url, '_blank');
  });
});
aboutExample.addEventListener('click', (e) => {
  e.preventDefault();
  closeAbout();
  invoke('open_example').catch(() => {});
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
  if (latestUpdateUrl) window.open(latestUpdateUrl, '_blank');
});
updateDismissEl.addEventListener('click', hideUpdateBanner);

async function runUpdateCheck(manual = false) {
  try {
    const info = await invoke('check_for_update');
    if (info) {
      showUpdateBanner(info);
    } else if (manual) {
      flashStatus('You’re up to date.');
    }
  } catch (_) {
    if (manual) flashStatus('Update check failed.');
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
}

// ==========================
//  Dirty / Auto-save / Scratch
// ==========================

function markDirty() {
  if (!isDirty) { isDirty = true; dirtyEl.classList.remove('hidden'); }
  resetAutoSave();
  resetScratchSave();
  updateStats();
  updatePreview();
}

function markClean() {
  isDirty = false;
  dirtyEl.classList.add('hidden');
  ipcClearScratch();
}

function resetAutoSave() {
  clearTimeout(autoSaveTimer);
  autoSaveTimer = setTimeout(() => {
    if (isDirty && currentFile) doSave(currentFile, getText());
  }, 2000);
}

function resetScratchSave() {
  clearTimeout(scratchTimer);
  scratchTimer = setTimeout(() => {
    if (isDirty) ipcSaveScratch(getText(), currentFile);
  }, 800);
}

async function doSave(path, content) {
  try { await ipcSaveFile(path, content); markClean(); flashStatus('Saved'); }
  catch (err) { flashStatus('Save failed: ' + (err?.message || err)); }
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
    const path = await ipcSaveFileAs(getText());
    if (path) {
      currentFile = path;
      await ipcAddRecent(path);
      ipcWatchFile(path);
      ipcSetTitle(basename(path).replace(/\.md$/, ''));
      markClean(); refreshStatusBar();
    }
  } catch (err) { flashStatus('Save failed: ' + (err?.message || err)); }
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
  clearTimeout(scratchTimer);
  setText('');
  currentFile = null;
  ipcUnwatchFile();
  await ipcClearScratch();
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
  view.dispatch({});
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

// ==========================
//  Global keyboard shortcuts (outside editor)
// ==========================

document.addEventListener('keydown', (e) => {
  const mod = e.metaKey || e.ctrlKey;

  if (e.key === 'Escape') {
    if (!aboutEl.classList.contains('hidden')) { closeAbout();      return; }
    if (isPreviewVisible)                      { togglePreview();   return; }
    if (isFocusMode)                           { toggleFocusMode(); return; }
    return;
  }

  if (mod && (e.key === '=' || e.key === '+')) { e.preventDefault(); changeFontSize(1);  return; }
  if (mod && e.key === '-')                     { e.preventDefault(); changeFontSize(-1); return; }

  if (mod && e.shiftKey && e.key === 'D') { e.preventDefault(); toggleFocusMode(); return; }
  if (mod && e.shiftKey && e.key === 'P') { e.preventDefault(); togglePreview();   return; }
  if (mod && e.shiftKey && e.key === 'L') { e.preventDefault(); toggleStats();     return; }
  if (mod && e.shiftKey && e.key === 'W') { e.preventDefault(); cycleWidth();      return; }
  if (mod && e.shiftKey && e.key === 'T') { e.preventDefault(); cycleTheme();      return; }
  if (mod && e.shiftKey && e.key === 'G') { e.preventDefault(); cycleWordGoal();   return; }
  if (mod && !e.shiftKey && e.key === 'p') { e.preventDefault(); openPalette();    return; }
});

// ==========================
//  IPC listeners
// ==========================

async function loadFile(payload) {
  if (isDirty) {
    const proceed = await confirmDiscard('Open new file?');
    if (!proceed) return;
  }
  setText(payload.content);
  currentFile = payload.path;
  ipcSetTitle(basename(payload.path).replace(/\.md$/, ''));
  ipcAddRecent(payload.path);
  ipcWatchFile(payload.path);
  markClean(); updateStats(); updatePreview(); refreshStatusBar();
  view.focus();
}

async function handleExternalChange(payload) {
  if (!currentFile || payload.path !== currentFile) return;
  if (payload.content === getText()) return;
  const message = isDirty
    ? 'File changed on disk:\n' + basename(currentFile) +
      '\n\nYour buffer has unsaved changes. Reload from disk and lose them?'
    : 'File changed on disk:\n' + basename(currentFile) + '\n\nReload?';
  const reload = await ask(message, { title: 'Loomings', kind: 'warning' });
  if (!reload) return;
  setText(payload.content);
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
    listen('open-palette',         ()  => openPalette()),
    listen('open-about',           ()  => openAbout()),
    listen('manual-update-check',  ()  => runUpdateCheck(true)),
    listen('open-url',             (e) => { if (e.payload) window.open(e.payload, '_blank'); }),
    listen('font-size',            (e) => changeFontSize(e.payload)),
    listen('request-close',     async () => {
      if (isDirty) {
        const proceed = await confirmDiscard('Quit Loomings?');
        if (!proceed) return;
      }
      clearTimeout(autoSaveTimer);
      clearTimeout(scratchTimer);
      await ipcClearScratch();
      await ipcConfirmQuit();
    }),
  ]);
}

// ==========================
//  Window drag (titlebar)
// ==========================

const titlebar = document.getElementById('titlebar');
if (titlebar) {
  titlebar.addEventListener('mousedown', async (e) => {
    if (e.button !== 0) return;
    const win = getCurrentWindow();
    if (e.detail === 2) {
      try { await win.toggleMaximize(); } catch (_) {}
      return;
    }
    try { await win.startDragging(); } catch (_) {}
  });
}

// ==========================
//  Init + scratch recovery
// ==========================

(async () => {
  await registerListeners();
  initAbout();
  setTimeout(() => runUpdateCheck(false), 3000);
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
        ipcSetTitle(basename(currentFile).replace(/\.md$/, ''));
        ipcWatchFile(currentFile);
      }
      markDirty();
    } else {
      await ipcClearScratch();
    }
  }
  updateStats(); updateCursorPos(); refreshStatusBar();
  view.focus();
  ipcSetTitle(currentFile ? basename(currentFile).replace(/\.md$/, '') : null);
})();
