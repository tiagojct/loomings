// ========================================
// Loomings — text statistics engine
// Pure functions for word counting, reading time, and selection metrics.
// ========================================

// Word tokens: a letter followed by letters, digits, apostrophes or hyphens,
// or a run of digits. Markdown's own punctuation (#, *, -, >, `, |, ---) never
// matches, so formatting a draft does not inflate the word count.
const WORD = /\p{L}[\p{L}\p{N}'’\-]*|\p{N}+/gu;

// List markers are structure, not prose, but a bare number does match WORD —
// so drop the markers before counting ("1. first" is one word, not two).
const LIST_MARKER = /^[ \t]{0,3}(?:[-*+]|\d+[.)])[ \t]+/gm;
// A link's destination is not prose: "[a link](https://example.com)" reads as
// two words, not five. Bare URLs collapse to one token each.
const LINK_DESTINATION = /\]\([^()\s]*\)/g;
const BARE_URL = /\bhttps?:\/\/\S+/gi;

/**
 * Counts words in a Markdown document, ignoring block and inline syntax.
 *
 * @param {string} text
 * @returns {number}
 */
export function countWords(text) {
  if (!text) return 0;
  const prose = text
    .replace(LINK_DESTINATION, '')
    .replace(BARE_URL, 'url')
    .replace(LIST_MARKER, '');
  const words = prose.match(WORD);
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
