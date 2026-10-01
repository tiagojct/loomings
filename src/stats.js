// ========================================
// Loomings — text statistics engine
// Pure functions for word counting, reading time, and selection metrics.
// ========================================

/**
 * Counts non-whitespace word tokens in a string.
 * Uses unicode-aware whitespace matching.
 *
 * @param {string} text
 * @returns {number}
 */
export function countWords(text) {
  if (!text) return 0;
  const words = text.match(/\S+/g);
  return words ? words.length : 0;
}

/**
 * Computes an estimated reading time string.
 *
 * @param {number} words
 * @param {number} [wpm=200]
 * @returns {string}
 */
export function readingTime(words, wpm = 200) {
  return words > 0 ? `~${Math.max(1, Math.ceil(words / wpm))} min` : '';
}
