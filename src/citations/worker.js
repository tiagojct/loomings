// ========================================
// Loomings — the citation session off the main thread
// Receives {id, type: 'sources', sources} and {id, type: 'analyse', text}.
// Each analyse gets the answer {id, report}. A sources message gets no
// answer: client.js sends an analyse after it. The session contains its own
// errors, so a bad style gives a note and this worker stays alive.
// {share, type: 'share', text} gets {share, shared}: the text for a share
// link, or null when it cannot be made.
// ========================================

import { createSession } from './session.js';

const session = createSession();

self.onmessage = (event) => {
  const { id, type, sources, text, share } = event.data;
  if (type === 'sources') {
    session.setSources(sources);
    return;
  }
  if (type === 'share') {
    /** @type {string|null} */
    let shared = null;
    try {
      shared = session.shareSource(text);
    } catch {
      // The caller falls back to the plain text.
    }
    self.postMessage({ share, shared });
    return;
  }
  self.postMessage({ id, report: session.analyse(text) });
};
