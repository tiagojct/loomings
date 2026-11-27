// ========================================
// Loomings — keep live preview work separate from visible content
// ========================================

/** @typedef {import('./citations/session.js').CitationReport} CitationReport */

/**
 * @typedef {{
 *   source: string,
 *   report: CitationReport|null,
 *   switched: boolean,
 * }} PreparedPreview
 */

/**
 * @param {{
 *   render: (source: string, report: CitationReport|null) => Promise<string|null>,
 *   isShown: () => boolean,
 *   apply: (html: string) => void,
 *   hasDiagrams: () => boolean,
 *   renderDiagrams: () => Promise<void>,
 *   afterDiagrams: () => void,
 * }} options
 */
export function createPreviewLifecycle(options) {
  // Request freshness changes on every update; content freshness changes only
  // when visible HTML changes or print takes over the preview element.
  let requestGeneration = 0;
  let contentGeneration = 0;
  /** @type {string|null} */
  let visibleHtml = null;
  let printing = false;

  return {
    /**
     * @param {{
     *   prepare: () => PreparedPreview|null,
     *   onlyIfChanged?: boolean,
     * }} request
     */
    async update({ prepare, onlyIfChanged = false }) {
      if (printing) return;
      const prepared = prepare();
      if (!prepared || !options.isShown()) return;

      const generation = ++requestGeneration;
      const html = await options.render(prepared.source, prepared.report);
      if (html === null || generation !== requestGeneration || printing || !options.isShown()) return;
      if (onlyIfChanged && !prepared.switched && html === visibleHtml) return;

      visibleHtml = html;
      const content = ++contentGeneration;
      options.apply(html);
      if (!options.hasDiagrams()) return;

      try {
        await options.renderDiagrams();
      } catch {
        return;
      }
      if (content !== contentGeneration) return;
      options.afterDiagrams();
    },

    beginPrint() {
      printing = true;
      requestGeneration++;
      contentGeneration++;
    },

    endPrint() {
      printing = false;
    },
  };
}
