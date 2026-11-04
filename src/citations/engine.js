// ========================================
// Loomings — citation engine
// Formats citations and a bibliography with citeproc. The engine is built
// once. Each render resets its state and sends the citations in document
// order, so two renders of the same input give the same output.
// Pure: no DOM, no Node or browser APIs (a worker and JavaScriptCore run it).
// Anchors from wrap_url_and_doi stay in the output: output.js filters them.
// ========================================

import CSL from 'citeproc';

/**
 * @typedef {import('./scan.js').Citation} Citation
 * @typedef {import('./bib.js').CslItem} CslItem
 */

/**
 * @param {{styleXml: string, localeXml: string, lang: string, items: CslItem[]}} options
 * @returns {{render(citations: Citation[]): {texts: string[], bibliography: string[]}}}
 */
export function createEngine({ styleXml, localeXml, lang, items }) {
  /** @type {Map<string, CslItem>} */
  const byId = new Map();
  for (const item of items) if (!byId.has(item.id)) byId.set(item.id, item);

  const engine = new CSL.Engine(
    { retrieveLocale: () => localeXml, retrieveItem: (/** @type {string} */ id) => byId.get(id) },
    styleXml,
    lang,
  );
  engine.opt.development_extensions.wrap_url_and_doi = true;

  /**
   * @param {Citation['items']} list
   * @param {boolean} affixes
   * @param {boolean} suppress
   */
  const toItems = (list, affixes, suppress) =>
    list.map((it) => {
      /** @type {Record<string, any>} */
      const o = { id: it.key };
      if (affixes) {
        if (it.prefix) o.prefix = it.prefix;
        if (it.suffix) o.suffix = it.suffix;
        if (it.locator) {
          o.locator = it.locator;
          o.label = it.label || 'page';
        }
      }
      if (suppress || it.suppressAuthor) o['suppress-author'] = true;
      return o;
    });

  return {
    render(citations) {
      // Unknown keys make citeproc throw, so they are removed first.
      const known = citations.map((c) => c.items.filter((it) => byId.has(it.key)));
      const used = [...new Set(known.flat().map((it) => it.key))];

      engine.restoreProcessorState([]);
      engine.updateItems(used);

      /** @type {string[][]} one entry per citation: the text of each of its clusters */
      const parts = [];
      /** @type {[number, number][]} cluster index to [citation, part] */
      const where = [];
      /** @type {[string, number][]} */
      const pre = [];
      let n = 0;
      const send = (/** @type {any[]} */ citationItems, /** @type {number} */ ci, /** @type {number} */ pi) => {
        const id = `c${n++}`;
        const result = engine.processCitationCluster(
          { citationID: id, citationItems, properties: { noteIndex: 0 } },
          pre.slice(),
          [],
        );
        pre.push([id, 0]);
        where.push([ci, pi]);
        // Text at an earlier index can change when a later cluster arrives.
        for (const [index, text] of result[1]) {
          const w = where[index];
          if (w) parts[w[0]][w[1]] = text;
        }
      };

      citations.forEach((c, ci) => {
        const list = known[ci];
        parts[ci] = [];
        if (!list.length) return;
        const sub = { ...c, items: list };
        if (c.bare) {
          // The author as author-only, then the rest with the author hidden.
          parts[ci] = ['', ''];
          send(list.map((it) => ({ id: it.key, 'author-only': true })), ci, 0);
          send(toItems(sub.items, true, true), ci, 1);
        } else {
          parts[ci] = [''];
          send(toItems(sub.items, true, false), ci, 0);
        }
      });

      const texts = parts.map((p) => p.filter((t) => t !== '').join(' '));
      const made = used.length ? engine.makeBibliography() : false;
      const bibliography = made ? made[1].slice() : [];
      return { texts, bibliography };
    },
  };
}
