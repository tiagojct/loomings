// CodeMirror styling from a palette: the syntax colours and the editor theme.
// Pure functions of the palette; editor.js swaps them in through compartments.

import { EditorView } from '@codemirror/view';
import { HighlightStyle } from '@codemirror/language';
import { tags as t } from '@lezer/highlight';
import { citationThemeRules } from './citations/editor.js';

export function makeHighlight(p) {
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
    { tag: t.link,       color: p.accentLight, textDecoration: 'underline' },
    { tag: t.url,        color: p.accentDim },
    { tag: t.quote,      color: p.fgDim,       fontStyle: 'italic' },
    { tag: t.processingInstruction, color: p.fgGhost },
    { tag: t.contentSeparator,      color: p.fgGhost },
    { tag: t.list,       color: p.marker },
  ]);
}

export function makeTheme(p, isDark) {
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
    '.cm-selectionBackground': { background: p.selection + ' !important' },
    '&.cm-focused .cm-selectionBackground': { background: p.selection + ' !important' },
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
    '.cm-search button:hover': { background: p.accent, color: p.onAccent },
    '.cm-search [name=close]': { color: p.fgDim },
    '.cm-searchMatch': { backgroundColor: p.accent + '40' },
    '.cm-searchMatch.cm-searchMatch-selected': { backgroundColor: p.accentLight + '70' },
    ...citationThemeRules(p),
  }, { dark: isDark });
}
