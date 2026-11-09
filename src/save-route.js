// ========================================
// Loomings — what Save should do for the buffer
// A file with a handle is written in place. A file opened where the browser
// has no picker is a copy: Save keeps it in this browser instead of starting
// a download. An untitled buffer picks a file where the browser can write
// one, and goes to the browser store everywhere else. Pure, so editor.js can
// keep the branching out of its save handler.
// ========================================

/**
 * @param {{file: string|null, docId: string|null, writable: boolean, hasFsa: boolean}} home
 *   writable: the open file has a handle that can be written
 *   hasFsa: the browser has the File System Access pickers
 * @returns {'save-now'|'save-as'|'save-in-browser'}
 */
export function saveAction({ file, docId, writable, hasFsa }) {
  if (docId) return 'save-now';
  if (file) return writable ? 'save-now' : 'save-in-browser';
  return hasFsa ? 'save-as' : 'save-in-browser';
}
