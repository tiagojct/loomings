// ========================================
// Loomings — export pages
// The standalone HTML page of the HTML export, and the colours that a diagram
// takes when the Word export draws it. Pure: strings in, strings out.
// ========================================

import { escapeHtml } from './html.js';
import { peleSeriesCss } from './mermaid.js';

/**
 * The standalone HTML page of the HTML export.
 *
 * @param {{title: string, body: string, p: Record<string, string>, lp: Record<string, string>}} options
 *   body: the rendered HTML; p: the roles of the current theme; lp: the roles of the family in light mode
 * @returns {string}
 */
export function exportHtmlPage({ title, body: rendered, p, lp }) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${escapeHtml(title)}</title>
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
  pre.mermaid { background: none; border: 0; padding: 0; text-align: center; }
  pre.mermaid svg { max-width: 100%; height: auto; }
  pre.mermaid-error p { margin: 0.75em 0 0; color: ${p.fgDim}; font-size: 0.9em; }
  .cite-missing { color: ${p.fgDim}; }
  .references { margin-top: 2.5em; }
  .csl-entry { margin-bottom: 0.6em; overflow-wrap: anywhere; }
  .csl-left-margin { float: left; width: 2.75em; }
  .csl-right-inline { margin-left: 2.75em; }
  .pele { --pele-bg: ${p.bg}; --pele-fg: ${p.fg}; --pele-muted: ${p.fgDim}; --pele-line: ${p.fgDim};
          --pele-surface: ${p.bgElev}; --pele-surface-alt: ${p.bgDeep}; --pele-border: ${p.border};
          --pele-accent: ${p.accent}; ${peleSeriesCss(p, p.bg)} }
  @media print { body { background: #fff; color: #000; }
    .cite-missing { color: ${lp.fgDim}; }
    .csl-entry { break-inside: avoid; }
    /* --pele-bg is the paper colour (#fff) of the body rule above. */
    .pele { --pele-bg: #fff; --pele-fg: ${lp.fg}; --pele-muted: ${lp.fgDim}; --pele-line: ${lp.fgDim}; --pele-surface: ${lp.bgElev};
            --pele-surface-alt: ${lp.bgDeep}; --pele-border: ${lp.border}; --pele-accent: ${lp.accent}; ${peleSeriesCss(lp, '#fff')} } }
</style>
</head>
<body>
${rendered}
</body>
</html>
`;}

/**
 * The CSS variables of a diagram, for the light palette on white, as the print
 * rule of the HTML export sets them. The Word export draws a diagram as a picture.
 *
 * @param {Record<string, string>} lp  roles in light mode
 * @returns {string}
 */
export function diagramCss(lp) {
  return `--pele-bg:#fff;--pele-fg:${lp.fg};--pele-muted:${lp.fgDim};--pele-line:${lp.fgDim};--pele-surface:${lp.bgElev};--pele-surface-alt:${lp.bgDeep};--pele-border:${lp.border};--pele-accent:${lp.accent};${peleSeriesCss(lp, '#fff')}`;
}

/**
 * Puts CSS declarations on the root element of an SVG. An existing `style`
 * attribute keeps its declarations, after the new ones, because a second
 * `style` attribute is not valid XML and the picture would not load.
 *
 * @param {string} svg
 * @param {string} css
 * @returns {string}
 */
export function withDiagramStyle(svg, css) {
  const open = /<svg\b(?:"[^"]*"|'[^']*'|[^"'>])*>/.exec(svg);
  if (!open) return svg;
  const tag = open[0];
  const quoted = /\sstyle\s*=\s*(?:"([^"]*)"|'([^']*)')/.exec(tag);
  const safe = css.replace(/"/g, "'");
  const next = quoted
    ? tag.replace(quoted[0], ` style="${escapeHtml(safe)};${escapeHtml(quoted[1] ?? quoted[2] ?? '')}"`)
    : tag.replace(/^<svg\b/, `<svg style="${escapeHtml(safe)}"`);
  return svg.slice(0, open.index) + next + svg.slice(open.index + tag.length);
}
