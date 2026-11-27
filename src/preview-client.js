// ========================================
// Loomings — coalesce citation-aware preview renders in a worker
// ========================================

import { citedHtml } from './citations/document.js';
import { renderPreview } from './markdown.js';

/**
 * @typedef {import('./citations/session.js').CitationReport} CitationReport
 * @typedef {{id: number, source: string, report: CitationReport|null,
 *   resolve: (html: string|null) => void}} RenderRequest
 */

function startWorker() {
  return new Worker(new URL('./preview-worker.js', import.meta.url), { type: 'module' });
}

/**
 * @param {{spawn?: () => Worker,
 *   fallback?: (source: string, report: CitationReport|null) => string}} [options]
 * @returns {{render(source: string, report: CitationReport|null): Promise<string|null>,
 *   reset(): void}}
 */
export function createPreviewClient(options = {}) {
  const spawn = options.spawn ?? startWorker;
  const fallback = options.fallback ?? ((source, report) => citedHtml(source, report, renderPreview));

  /** @type {Worker|null} */
  let worker = null;
  /** @type {RenderRequest|null} */
  let active = null;
  /** @type {RenderRequest|null} */
  let pending = null;
  let unavailable = false;
  let nextId = 1;

  /** @param {RenderRequest} request */
  function useFallback(request) {
    try {
      request.resolve(fallback(request.source, request.report));
    } catch {
      request.resolve(null);
    }
  }

  function terminateWorker() {
    const current = worker;
    worker = null;
    if (!current) return;
    try {
      current.onmessage = null;
      current.onerror = null;
      current.terminate();
    } catch {
      // A failed worker is already unusable.
    }
  }

  /**
   * @param {Worker|null} [failedWorker]
   */
  function failWorker(failedWorker = null) {
    if (failedWorker && worker !== failedWorker) return;
    unavailable = true;
    terminateWorker();

    const failedActive = active;
    const failedPending = pending;
    const latest = failedPending ?? failedActive;
    active = null;
    pending = null;

    if (failedPending && failedActive) failedActive.resolve(null);
    if (latest) useFallback(latest);
  }

  function start() {
    try {
      const instance = spawn();
      worker = instance;
      instance.onmessage = (event) => receive(instance, event.data);
      instance.onerror = () => failWorker(instance);
      return true;
    } catch {
      failWorker();
      return false;
    }
  }

  /**
   * @param {Worker} instance
   * @param {{id?: number, html?: string, error?: string}|null} response
   */
  function receive(instance, response) {
    if (worker !== instance || !active || !response || response.id !== active.id) return;

    const answered = active;
    const next = pending;
    active = next;
    pending = null;

    if (next) {
      answered.resolve(null);
      dispatch();
      return;
    }

    if (typeof response.error === 'string') {
      answered.resolve(null);
    } else {
      answered.resolve(typeof response.html === 'string' ? response.html : null);
    }
  }

  function dispatch() {
    if (!active) return;
    if (unavailable) {
      const latest = pending ?? active;
      active = null;
      pending = null;
      if (latest) useFallback(latest);
      return;
    }

    if (!worker && !start()) return;
    const current = worker;
    if (!current) return;

    try {
      current.postMessage({
        id: active.id,
        source: active.source,
        report: active.report,
      });
    } catch {
      failWorker(current);
    }
  }

  return {
    /**
     * @param {string} source
     * @param {CitationReport|null} report
     * @returns {Promise<string|null>}
     */
    render(source, report) {
      return new Promise((resolve) => {
        const request = { id: nextId++, source, report, resolve };
        if (unavailable) {
          useFallback(request);
          return;
        }

        if (active) {
          if (pending) pending.resolve(null);
          pending = request;
          return;
        }

        active = request;
        dispatch();
      });
    },

    reset() {
      const requests = [active, pending];
      active = null;
      pending = null;
      terminateWorker();
      unavailable = false;
      for (const request of requests) request?.resolve(null);
    },
  };
}
