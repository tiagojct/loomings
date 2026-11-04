// ========================================
// Loomings — the citation session off the main thread
// Receives {id, type: 'sources', sources} and {id, type: 'analyse', text}.
// Each analyse gets the answer {id, report}. A sources message gets no
// answer: client.js sends an analyse after it. The session contains its own
// errors, so a bad style gives a note and this worker stays alive.
// ========================================

import { createSession } from './session.js';

const session = createSession();

self.onmessage = (event) => {
  const { id, type, sources, text } = event.data;
  if (type === 'sources') {
    session.setSources(sources);
    return;
  }
  self.postMessage({ id, report: session.analyse(text) });
};
