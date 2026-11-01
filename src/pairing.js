// ========================================
// Loomings — paired lines (Split view)
// The live preview's top-level blocks carry their source lines
// (data-line, data-line-end; see renderPreview in markdown.js). These helpers
// find the block made from a source line, the same way the native app does.
// ========================================

/** @typedef {{line: number, end: number}} PreviewBlock  0-based, end exclusive */

/**
 * The top-level blocks of rendered preview HTML, or of a preview element, in
 * document order.
 *
 * @param {string|ParentNode} source
 * @returns {PreviewBlock[]}
 */
export function previewBlocks(source) {
  if (typeof source === 'string') {
    return [...source.matchAll(/data-line="(\d+)" data-line-end="(\d+)"/g)]
      .map((m) => ({ line: Number(m[1]), end: Number(m[2]) }));
  }
  return /** @type {HTMLElement[]} */ (Array.from(source.querySelectorAll('[data-line-end]')))
    .map((node) => ({ line: Number(node.dataset.line), end: Number(node.dataset.lineEnd) }));
}

/**
 * The index of the block whose lines contain `line`, or -1 (a blank line
 * between blocks, or past the end). Blocks are sorted and do not overlap.
 *
 * @param {PreviewBlock[]} blocks
 * @param {number} line 0-based source line
 * @returns {number}
 */
export function blockForLine(blocks, line) {
  let low = 0;
  let high = blocks.length - 1;
  while (low <= high) {
    const mid = (low + high) >> 1;
    const block = blocks[mid];
    if (line < block.line) high = mid - 1;
    else if (line >= block.end) low = mid + 1;
    else return mid;
  }
  return -1;
}
