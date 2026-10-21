// ========================================
// Loomings — document session
// The rules that keep unsaved work safe: when the buffer counts as dirty,
// when a draft goes to IndexedDB, when the buffer is written to its home,
// and what a slow write is allowed to touch once the buffer has moved on.
//
// Headless and injectable: editor.js supplies the text, the home and the two
// writes; this module owns the discipline — and therefore can be tested
// without a DOM or a CodeMirror view.
// ========================================

export const SCRATCH_DELAY = 800;
export const SAVE_DELAY = 2000;
const DISCARD_WAIT = 2000;

/** @param {unknown} err */
const messageOf = (err) => (err && /** @type {Error} */ (err).message) || String(err);

/**
 * @param {object} ports
 * @param {() => string} ports.content              text of the buffer right now
 * @param {() => {file: string|null, docId: string|null}} ports.target  where it lives
 * @param {(text: string) => Promise<unknown>} ports.write   write to that home
 * @param {{saveScratch: (text: string, file: string|null) => Promise<unknown>, clearScratch: () => Promise<unknown>}} ports.storage
 * @param {() => void} [ports.onDirty]
 * @param {() => void} [ports.onClean]
 * @param {(text: string) => void} [ports.onSaved]
 * @param {(message: string) => void} [ports.onError]
 */
export function createSession(ports) {
  const {
    content, target, write, storage,
    onDirty = () => {}, onClean = () => {}, onSaved = () => {}, onError = () => {},
  } = ports;

  let dirty = false;
  // Bumped whenever the buffer is repointed at a different document (New,
  // Open, reload, Save As). Every async write captures it first and checks it
  // after: a save or draft write that lands late must not report onto the
  // buffer that replaced the one it was aimed at.
  let generation = 0;

  /** @type {string|null} */ let lastScratch = null;
  /** @type {Promise<void>|null} */ let scratchInFlight = null;
  /** @type {Promise<boolean>|null} */ let saveInFlight = null;
  /** @type {ReturnType<typeof setTimeout>|null} */ let scratchTimer = null;
  /** @type {ReturnType<typeof setTimeout>|null} */ let saveTimer = null;

  function setDirty(next) {
    if (dirty === next) return;
    dirty = next;
    if (next) onDirty(); else onClean();
  }

  /** @param {ReturnType<typeof setTimeout>|null} timer */
  function stop(timer) {
    if (timer !== null) clearTimeout(timer);
    return null;
  }

  function cancelTimers() {
    scratchTimer = stop(scratchTimer);
    saveTimer = stop(saveTimer);
  }

  function hasHome() {
    const home = target();
    return Boolean(home && (home.file || home.docId));
  }

  // Drafts are chained, never concurrent: two overlapping writes could land
  // out of order and leave the older text behind. Nothing thrown here escapes
  // — a draft that cannot be stored is a message, not a broken boot.
  function writeScratchNow() {
    const text = content();
    if (text === lastScratch) return Promise.resolve();
    lastScratch = text;
    const gen = generation;
    const previous = scratchInFlight;

    const run = (async () => {
      if (previous) await previous;
      try {
        await storage.saveScratch(text, target().file);
        // A discard that ran while this write was in flight could not clear
        // text it had not seen land — clear it now, so a stalled write can
        // never resurrect an abandoned buffer's draft.
        if (gen !== generation) await storage.clearScratch();
      } catch (err) {
        // Let the next edit or flush retry the same text instead of
        // remembering a draft that never landed.
        if (lastScratch === text) lastScratch = null;
        onError('Draft not kept: ' + messageOf(err));
      }
    })();
    scratchInFlight = run;
    return run;
  }

  async function clearScratchQuietly() {
    try {
      if (scratchInFlight) await scratchInFlight;
      await storage.clearScratch();
    } catch (_) {
      // The write path has already reported the failure.
    }
  }

  function noteSaved(text) {
    cancelTimers();
    lastScratch = text;
    setDirty(false);
    void clearScratchQuietly();
  }

  function markEdited() {
    setDirty(true);

    saveTimer = stop(saveTimer);
    saveTimer = setTimeout(() => {
      saveTimer = null;
      if (dirty && hasHome()) void saveNow();
    }, SAVE_DELAY);

    scratchTimer = stop(scratchTimer);
    scratchTimer = setTimeout(() => {
      scratchTimer = null;
      if (dirty) void writeScratchNow();
    }, SCRATCH_DELAY);
  }

  function flushScratch() {
    if (!dirty) return Promise.resolve();
    scratchTimer = stop(scratchTimer);
    return writeScratchNow();
  }

  async function saveNow() {
    if (!hasHome()) return false;
    // An explicit Cmd+S and the autosave timer can fire close enough together
    // that two writes to the same handle would overlap; one at a time.
    if (saveInFlight) await saveInFlight;

    const gen = generation;
    const text = content();

    const run = (async () => {
      try {
        await write(text);
      } catch (err) {
        if (gen === generation) onError('Save failed: ' + messageOf(err));
        return false;
      }
      if (gen !== generation) return true; // the buffer moved on; nothing to report
      // An edit landed while the write was in flight, so what is on disk is
      // not what is in the buffer: stay dirty and leave the timers that edit
      // armed alone, or the newest text is neither saved nor drafted.
      if (content() !== text) return true;
      noteSaved(text);
      onSaved(text);
      return true;
    })();

    saveInFlight = run;
    try {
      return await run;
    } finally {
      if (saveInFlight === run) saveInFlight = null;
    }
  }

  // Clean the buffer without touching its home or its draft. Used after a
  // fresh buffer is loaded, where setText has just made it look edited.
  function markClean() {
    cancelTimers();
    setDirty(false);
  }

  // Repoint: the buffer now belongs to another document. Bump first so
  // anything still in flight knows its result is history.
  function repoint() {
    generation++;
    cancelTimers();
    lastScratch = null;
    setDirty(false);
  }

  // The buffer was written to a new home by the caller (Save As, Save a copy
  // here): adopt that as the saved state.
  function adopt(text) {
    generation++;
    cancelTimers();
    lastScratch = text;
    setDirty(false);
    void clearScratchQuietly();
  }

  // Drop the draft for the document we are leaving behind, so a later crash
  // cannot offer to "recover" content the user already discarded.
  async function discardScratch() {
    cancelTimers();
    generation++;
    const pending = scratchInFlight;
    if (pending) {
      /** @type {ReturnType<typeof setTimeout>|null} */
      let timer = null;
      await Promise.race([
        pending,
        new Promise((resolve) => { timer = setTimeout(resolve, DISCARD_WAIT); }),
      ]);
      stop(timer);
    }
    lastScratch = null;
    try {
      await storage.clearScratch();
    } catch (err) {
      onError('Could not clear the draft: ' + messageOf(err));
    }
  }

  return {
    markEdited,
    markClean,
    flushScratch,
    discardScratch,
    saveNow,
    repoint,
    adopt,
    isDirty: () => dirty,
  };
}
