// ========================================
// Loomings — HTML escaping
// One escaper for both text and attribute contexts. Quotes are included
// because menu rows interpolate a document's title into aria-label="…",
// where an unescaped quote ends the attribute and starts a new one.
// ========================================

const ENTITIES = {
  '&': '&amp;',
  '<': '&lt;',
  '>': '&gt;',
  '"': '&quot;',
  "'": '&#39;',
};

/**
 * Escapes a value for interpolation into HTML text or a quoted attribute.
 *
 * @param {unknown} value
 * @returns {string}
 */
export function escapeHtml(value) {
  if (value === null || value === undefined) return '';
  return String(value).replace(/[&<>"']/g, (ch) => ENTITIES[ch]);
}
