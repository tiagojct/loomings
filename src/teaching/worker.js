// ========================================
// Loomings — the teaching analysis off the main thread
// Receives {id, text, attached}, answers {id, report}. editor.js keeps the
// id of the latest request and drops older answers.
// ========================================

import { analyse } from './report.js';

self.onmessage = (event) => {
  const { id, text, attached } = event.data;
  self.postMessage({ id, report: analyse(text, attached) });
};
