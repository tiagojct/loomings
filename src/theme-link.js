// ========================================
// Loomings — theme deep links
// `/app/?theme=goney&mode=dark` opens the editor in a named family and mode,
// which is what the landing page's ten colour cards link to. Pure functions:
// the caller decides what to do with an unknown family, and the URL is
// stripped before anything else reads it.
// ========================================

/**
 * @param {string} search  a location.search ("?theme=…") or ""
 * @param {{families: string[], modes: string[]}} known
 * @returns {{family: string|null, mode: string|null, present: boolean}}
 */
export function readThemeParams(search, { families, modes }) {
  const params = new URLSearchParams(search);
  const family = params.get('theme');
  const mode = params.get('mode');
  return {
    family: typeof family === 'string' && families.includes(family) ? family : null,
    mode: typeof mode === 'string' && modes.includes(mode) ? mode : null,
    present: params.has('theme') || params.has('mode'),
  };
}

/**
 * The app URL with `theme` and `mode` removed, everything else (a lesson, a
 * share fragment) kept. Returns `href` untouched when there is nothing to
 * strip.
 *
 * @param {string} href
 * @returns {string}
 */
export function withoutThemeParams(href) {
  const url = new URL(href);
  if (!url.searchParams.has('theme') && !url.searchParams.has('mode')) return href;
  url.searchParams.delete('theme');
  url.searchParams.delete('mode');
  return url.pathname + url.search + url.hash;
}
