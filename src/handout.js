// ========================================
// Loomings — the printed handout's page
// Page size, page numbers and the family's light colours, written as a
// style sheet just before printing (see printPreview in editor.js). As the
// native handout: A4, or Letter where the measurement system is the US one;
// "Title · page N of M" at the foot of each page. Margin boxes are drawn by
// browsers that support them; Safari prints without page numbers.
// ========================================

/**
 * @param {string} language a BCP 47 tag, e.g. navigator.language
 * @returns {'A4'|'letter'}
 */
export function paperFor(language) {
  try {
    const region = new Intl.Locale(language).maximize().region;
    return region && ['US', 'LR', 'MM'].includes(region) ? 'letter' : 'A4';
  } catch (_) {
    return 'A4';
  }
}

/** A CSS string body: backslashes and quotes escaped, line breaks as spaces. */
const cssString = (/** @type {string} */ text) => text.replace(/[\\"]/g, '\\$&').replace(/[\r\n]+/g, ' ');

/**
 * @param {{title: string, palette: Record<string, string>, paper: string}} options
 * @returns {string}
 */
export function handoutCss({ title, palette: p, paper }) {
  const footer = title
    ? `"${cssString(title)} \\00B7  page " counter(page) " of " counter(pages)`
    : '"page " counter(page) " of " counter(pages)';
  return `@page { size: ${paper}; margin: 19mm 19mm 23mm;
  @bottom-center { content: ${footer}; font-family: sans-serif; font-size: 8pt; color: ${p.fgDim}; } }
@media print { :root {
  --print-fg: ${p.fg}; --print-dim: ${p.fgDim}; --print-heading: ${p.heading}; --print-emphasis: ${p.emphasis};
  --print-code: ${p.code}; --print-link: ${p.accent}; --print-code-bg: ${p.bgDeep}; --print-border: ${p.border};
} }`;
}
