// ========================================
// Loomings — writing preferences
// The values the writer changes from the keyboard, with the projector rule:
// projector mode is a set of effective values, so it must not move a stored
// font size or column width. Pure; editor.js keeps the DOM and storage.
// ========================================

export const FONT_MIN = 11;
export const FONT_MAX = 24;
export const WIDTHS = ['wide', 'normal', 'narrow'];

/**
 * @param {number} size  the stored size
 * @param {number} delta  -1 or 1
 * @param {boolean} locked  projector mode is on
 * @returns {number|null} null: keep the stored value
 */
export function nextFontSize(size, delta, locked) {
  if (locked) return null;
  return Math.min(FONT_MAX, Math.max(FONT_MIN, size + delta));
}

/**
 * @param {string} width  the stored width
 * @param {boolean} locked  projector mode is on
 * @returns {string|null} null: keep the stored value
 */
export function nextWidth(width, locked) {
  if (locked) return null;
  const index = WIDTHS.indexOf(width);
  return WIDTHS[(index + 1) % WIDTHS.length];
}
