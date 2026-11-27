// ========================================
// Loomings — render citation-aware preview HTML off the main thread
// ========================================

import { citedHtml } from './citations/document.js';
import { renderPreview } from './markdown.js';

self.onmessage = (event) => {
  const { id, source, report } = event.data;
  try {
    self.postMessage({ id, html: citedHtml(source, report, renderPreview) });
  } catch (error) {
    self.postMessage({ id, error: String(error) });
  }
};
