// ========================================
// Loomings — browser adapter
// Everything that touches the browser's file, storage and window APIs:
// File System Access (Chromium) with input[type=file]/download fallback,
// IndexedDB for scratch/recents, document.title, window.confirm.
// editor.js never calls these APIs directly.
// ========================================

import exampleContent from '../examples/loomings.md?raw';
import { version as pkgVersion } from '../package.json';

export const hasFileSystemAccess = typeof window !== 'undefined' && 'showOpenFilePicker' in window && 'showSaveFilePicker' in window;

const OPEN_TYPES = {
  description: 'Markdown',
  accept: { 'text/markdown': ['.md', '.markdown', '.mdown', '.mkd', '.qmd', '.rmd', '.txt'] },
};
const OPENABLE = /\.(md|markdown|mdown|mkd|qmd|rmd|txt)$/i;

// The handle behind the currently open file (Chromium only) — paired with
// editor.js's own `currentFile` display-string. Only this module reads or
// mutates it; editor.js never sees a FileSystemFileHandle directly.
/** @type {FileSystemFileHandle|null} */
let currentFileHandle = null;

function downloadBlob(content, filename, mime) {
  const blob = new Blob([content], { type: mime });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

// ==========================
//  IndexedDB (scratch + recents, one tiny "kv" store)
// ==========================

const DB_NAME = 'loomings-web';
const STORE = 'kv';
const DOC_CONTENT_PREFIX = 'doc_content:';

/** @type {Promise<IDBDatabase>|null} */
let dbPromise = null;

function openDb() {
  if (!dbPromise) {
    dbPromise = new Promise((resolve, reject) => {
      const req = indexedDB.open(DB_NAME, 1);
      req.onupgradeneeded = () => { req.result.createObjectStore(STORE); };
      req.onsuccess = () => {
        const db = req.result;
        db.onversionchange = () => {
          db.close();
          dbPromise = null;
        };
        db.onclose = () => {
          dbPromise = null;
        };
        resolve(db);
      };
      req.onerror = () => {
        dbPromise = null;
        reject(req.error);
      };
    });
  }
  return dbPromise;
}

export function _resetDbForTesting() {
  if (dbPromise) {
    dbPromise.then((db) => db.close()).catch(() => {});
    dbPromise = null;
  }
}

/**
 * @param {string} key
 * @returns {Promise<any>}
 */
export async function idbGet(key) {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE, 'readonly');
    const req = tx.objectStore(STORE).get(key);
    req.onsuccess = () => resolve(req.result ?? null);
    req.onerror = () => reject(req.error);
    tx.onerror = () => reject(tx.error);
  });
}

/**
 * @param {string} key
 * @param {unknown} value
 * @returns {Promise<void>}
 */
export async function idbSet(key, value) {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE, 'readwrite');
    tx.objectStore(STORE).put(value, key);
    tx.oncomplete = () => resolve();
    // `tx.error` is null for an aborted-but-clean transaction, so give the
    // caller a real Error instead of rejecting with undefined.
    tx.onerror = () => reject(tx.error || new Error('IndexedDB write failed'));
    tx.onabort = () => reject(tx.error || new Error('IndexedDB transaction aborted'));
  });
}

/**
 * @param {string} key
 * @returns {Promise<void>}
 */
export async function idbDelete(key) {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE, 'readwrite');
    tx.objectStore(STORE).delete(key);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error || new Error('IndexedDB delete failed'));
    tx.onabort = () => reject(tx.error || new Error('IndexedDB transaction aborted'));
  });
}

/**
 * All values whose key starts with a prefix.
 * @param {string} prefix
 * @returns {Promise<any[]>}
 */
async function idbValuesWithPrefix(prefix) {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE, 'readonly');
    const req = tx.objectStore(STORE).getAll(IDBKeyRange.bound(prefix, prefix + '\uffff'));
    req.onsuccess = () => resolve(req.result ?? []);
    req.onerror = () => reject(req.error);
    tx.onerror = () => reject(tx.error);
  });
}

// ==========================
//  Window-ish
// ==========================

export async function getVersion() { return pkgVersion; }

export async function openUrl(url) {
  window.open(url, '_blank', 'noopener,noreferrer');
}

export async function ask(message) {
  // Blunter than a styled dialog (blocks the main thread) but correct — a
  // custom in-page modal is a nice-to-have, not required for this to work.
  return window.confirm(message);
}

export async function setTitle(title) {
  document.title = title ? `${title} · Loomings` : 'Loomings';
}

// ==========================
//  File I/O
// ==========================

export async function saveFile(path, content) {
  if (!currentFileHandle) return saveFileAs(content);
  const perm = await currentFileHandle.queryPermission({ mode: 'readwrite' });
  if (perm !== 'granted') {
    const granted = await currentFileHandle.requestPermission({ mode: 'readwrite' });
    if (granted !== 'granted') throw new Error('Permission to write this file was not granted');
  }
  const writable = await currentFileHandle.createWritable();
  await writable.write(content);
  await writable.close();
  return path;
}

export async function saveFileAs(content, suggestedName = 'untitled.md') {
  if (hasFileSystemAccess) {
    let handle;
    try {
      handle = await window.showSaveFilePicker({ types: [OPEN_TYPES], suggestedName });
    } catch (err) {
      // Only a user cancel is silent; a blocked or failed picker must reach
      // the caller so it can be reported instead of looking like a cancel.
      if (err?.name === 'AbortError') return null;
      throw err;
    }
    const writable = await handle.createWritable();
    await writable.write(content);
    await writable.close();
    currentFileHandle = handle;
    return handle.name;
  }
  // No File System Access API (Firefox/Safari): a plain download, not an
  // in-place save. The caller surfaces this distinction to the user.
  downloadBlob(content, suggestedName, 'text/markdown');
  currentFileHandle = null;
  return null;
}

export async function openFile() {
  if (hasFileSystemAccess) {
    let handle;
    try {
      [handle] = await window.showOpenFilePicker({ types: [OPEN_TYPES] });
    } catch (err) {
      if (err?.name === 'AbortError') return null;
      throw err;
    }
    const file = await handle.getFile();
    const content = await file.text();
    // Adopt only after a successful read: a handle whose file vanished between
    // picking and reading must not become the target of the next Save.
    currentFileHandle = handle;
    return { path: file.name, content };
  }
  return new Promise((resolve) => {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = '.md,.markdown,.mdown,.mkd,.qmd,.rmd,.txt';
    input.addEventListener('change', async () => {
      const file = input.files?.[0];
      if (!file) { resolve(null); return; }
      currentFileHandle = null;
      resolve({ path: file.name, content: await file.text() });
    });
    input.click();
  });
}

// Adopts a handle that arrived from outside the pickers (PWA file_handlers
// launch queue, drag-and-drop) so later Save writes back to it.
export async function openHandle(handle) {
  if (!handle || handle.kind !== 'file' || !OPENABLE.test(handle.name)) return null;
  const file = await handle.getFile();
  const content = await file.text();
  currentFileHandle = handle;
  return { path: file.name, content };
}

// Detaches the buffer from any file handle — used when loading content
// that has no file behind it (example, lesson, shared link).
export function forgetFile() { currentFileHandle = null; }

export async function openExample() {
  currentFileHandle = null;
  return { path: '', content: exampleContent };
}

export async function downloadHtml(content, suggestedName) {
  downloadBlob(content, suggestedName, 'text/html');
  return suggestedName;
}

export async function downloadMarkdown(content, suggestedName) {
  downloadBlob(content, suggestedName, 'text/markdown');
  return suggestedName;
}

// ==========================
//  Recents (Chromium only — handles are structured-cloneable into IndexedDB)
// ==========================

export async function addRecent(filePath) {
  if (!currentFileHandle) return;
  try {
    const recents = (await idbGet('recents')) || [];
    const next = [
      { name: filePath, handle: currentFileHandle, lastOpened: Date.now() },
      ...recents.filter((r) => r.name !== filePath),
    ].slice(0, 10);
    await idbSet('recents', next);
  } catch (_) {
    // Recents are a convenience: losing one must never fail the open/save
    // that triggered it, nor surface as an unhandled rejection.
  }
}

export async function getRecents() {
  try {
    return (await idbGet('recents')) || [];
  } catch (_) {
    return [];
  }
}

// Reconnects a stored recent — requestPermission needs the click that
// triggered this call, so callers must invoke it directly from a click
// handler, not after an intervening await. Returns null when the file is
// gone or permission was declined, and drops the dead entry so the menu
// stops offering a row that can never open.
export async function openRecent(entry) {
  const forget = async () => {
    try {
      const recents = (await idbGet('recents')) || [];
      await idbSet('recents', recents.filter((r) => r.name !== entry.name));
    } catch (_) {}
  };
  try {
    const granted = await entry.handle.requestPermission({ mode: 'readwrite' });
    if (granted !== 'granted') {
      await forget();
      return null;
    }
    const file = await entry.handle.getFile();
    const content = await file.text();
    // Only now is this handle the file the buffer belongs to; assigning it
    // before the read could aim the next Save at a file it never opened.
    currentFileHandle = entry.handle;
    return { path: file.name, content };
  } catch (_) {
    // Revoked permission, a moved file, or a handle the browser no longer
    // accepts — all of them mean this row is finished.
    await forget();
    return null;
  }
}

// ==========================
//  Documents kept in this browser (IndexedDB)
//  {id, title, content, created, updated} — the only save target on
//  browsers without the File System Access API, and a drafts shelf on
//  the others. Newest first.
// ==========================

export async function listDocuments() {
  try {
    const raw = (await idbGet('documents')) || [];
    return raw.map((d) => ({
      id: d.id,
      title: d.title,
      created: d.created,
      updated: d.updated,
    }));
  } catch (_) {
    return [];
  }
}

export async function getDocument(id) {
  const meta = (await listDocuments()).find((d) => d.id === id);
  if (!meta) return null;
  let content = null;
  try {
    content = await idbGet(DOC_CONTENT_PREFIX + id);
  } catch (_) {}

  if (content === null) {
    try {
      const raw = (await idbGet('documents')) || [];
      const legacy = raw.find((d) => d.id === id);
      if (legacy && legacy.content !== undefined) {
        content = legacy.content;
        idbSet(DOC_CONTENT_PREFIX + id, content).catch(() => {});
      }
    } catch (_) {}
  }
  return { ...meta, content: content ?? '' };
}

export async function putDocument({ id, title, content }) {
  const raw = (await idbGet('documents')) || [];
  const now = Date.now();
  const existing = id ? raw.find((d) => d.id === id) : null;
  const docId = existing ? existing.id : (crypto.randomUUID ? crypto.randomUUID() : String(now) + Math.random().toString(16).slice(2));
  const docMeta = {
    id: docId,
    title,
    created: existing ? existing.created : now,
    updated: now,
  };
  await idbSet(DOC_CONTENT_PREFIX + docId, content);
  const next = [
    docMeta,
    ...raw.filter((d) => d.id !== docId).map((d) => ({
      id: d.id,
      title: d.title,
      created: d.created,
      updated: d.updated,
    })),
  ];
  await idbSet('documents', next);
  return { ...docMeta, content };
}

export async function deleteDocument(id) {
  const raw = (await idbGet('documents')) || [];
  await Promise.allSettled([
    idbDelete(DOC_CONTENT_PREFIX + id),
    idbSet('documents', raw.filter((d) => d.id !== id)),
  ]);
}

// ==========================
//  Citation files (.bib and .csl) kept in this browser
//  Key `citation-file:<name>`. A record is {name, kind, text, handle?,
//  encodingNote?, saved}. Every call is contained: a failure gives an
//  empty list or false, never a rejection.
// ==========================

const CITATION_PREFIX = 'citation-file:';
const CITATION_FILE = /\.(bib|csl)$/i;
const CITATION_TYPES = { description: 'Citation files', accept: { 'text/plain': ['.bib', '.csl'] } };

/**
 * Decodes the bytes of a citation file. UTF-8 first, then windows-1252.
 * A BOM is removed.
 *
 * @param {ArrayBuffer|Uint8Array} bytes
 * @returns {{text: string, encodingNote: boolean}}
 */
export function decodeCitationBytes(bytes) {
  let text;
  let encodingNote = false;
  const b = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  if (b.length >= 2 && ((b[0] === 0xff && b[1] === 0xfe) || (b[0] === 0xfe && b[1] === 0xff))) {
    const text16 = new TextDecoder(b[0] === 0xff ? 'utf-16le' : 'utf-16be').decode(b);
    return { text: text16.charCodeAt(0) === 0xfeff ? text16.slice(1) : text16, encodingNote: false };
  }
  try {
    text = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes);
  } catch (_) {
    text = new TextDecoder('windows-1252').decode(bytes);
    encodingNote = true;
  }
  if (text.charCodeAt(0) === 0xfeff) text = text.slice(1);
  return { text, encodingNote };
}

/** @param {string} name @returns {'bib'|'csl'|null} */
function citationKind(name) {
  const m = CITATION_FILE.exec(name);
  return m ? /** @type {'bib'|'csl'} */ (m[1].toLowerCase()) : null;
}

/** @param {File} file */
async function readCitationFile(file) {
  return decodeCitationBytes(await file.arrayBuffer());
}

/**
 * @returns {Promise<{name: string, kind: 'bib'|'csl', text: string, handle?: any, encodingNote?: boolean, saved: number}[]>}
 */
export async function listCitationFiles() {
  try {
    const all = await idbValuesWithPrefix(CITATION_PREFIX);
    return all
      .filter((r) => r && typeof r.name === 'string' && typeof r.text === 'string')
      .sort((a, b) => a.name.localeCompare(b.name));
  } catch (_) {
    return [];
  }
}

/**
 * @param {{name: string, kind: 'bib'|'csl', text: string, handle?: any, encodingNote?: boolean}} file
 * @returns {Promise<boolean>} false when the write failed
 */
export async function saveCitationFile({ name, kind, text, handle, encodingNote }) {
  try {
    /** @type {any} */
    const record = { name, kind, text, saved: Date.now() };
    if (handle) record.handle = handle;
    if (encodingNote) record.encodingNote = true;
    try {
      await idbSet(CITATION_PREFIX + name, record);
    } catch (err) {
      // A handle the browser cannot clone: keep the text without it.
      if (!handle) throw err;
      delete record.handle;
      await idbSet(CITATION_PREFIX + name, record);
    }
    // Names are equal when they differ only in case: remove the old record
    // only after the new one is written.
    const lower = name.toLowerCase();
    for (const old of await listCitationFiles()) {
      if (old.name !== name && old.name.toLowerCase() === lower) await idbDelete(CITATION_PREFIX + old.name);
    }
    return true;
  } catch (_) {
    return false;
  }
}

/** @param {string} name @returns {Promise<boolean>} */
export async function deleteCitationFile(name) {
  try {
    await idbDelete(CITATION_PREFIX + name);
    return true;
  } catch (_) {
    return false;
  }
}

// Reads the stored handles again. It never asks for permission: a handle
// without granted read permission is skipped. Returns the changed names.
export async function refreshCitationFiles() {
  /** @type {string[]} */
  const changed = [];
  for (const rec of await listCitationFiles()) {
    if (!rec.handle) continue;
    try {
      if ((await rec.handle.queryPermission({ mode: 'read' })) !== 'granted') continue;
      const { text, encodingNote } = await readCitationFile(await rec.handle.getFile());
      if (text === rec.text) continue;
      const saved = await saveCitationFile({ name: rec.name, kind: rec.kind, text, handle: rec.handle, encodingNote });
      if (saved) changed.push(rec.name);
    } catch (_) {
      // A moved or deleted file: keep the stored copy.
    }
  }
  return changed;
}

/**
 * Lets the user pick a .bib or .csl file and stores it.
 * @returns {Promise<{name: string, kind: 'bib'|'csl', text: string, encodingNote: boolean, stored: boolean}|null>}
 *   null on cancel, on a wrong file type or when the read failed. stored is false when the write failed.
 */
export async function pickCitationFile() {
  try {
    /** @type {any} */
    let handle = null;
    /** @type {File|null} */
    let file = null;
    if (hasFileSystemAccess) {
      try {
        [handle] = await window.showOpenFilePicker({ types: [CITATION_TYPES] });
      } catch (err) {
        if (err?.name === 'AbortError') return null;
        throw err;
      }
      file = await handle.getFile();
    } else {
      file = await new Promise((resolve) => {
        const input = document.createElement('input');
        input.type = 'file';
        input.accept = '.bib,.csl';
        input.style.display = 'none';
        const done = (/** @type {File|null} */ f) => { input.remove(); resolve(f); };
        input.addEventListener('change', () => done(input.files?.[0] ?? null));
        input.addEventListener('cancel', () => done(null));
        document.body.appendChild(input);
        input.click();
      });
    }
    if (!file) return null;
    const kind = citationKind(file.name);
    if (!kind) return null;
    const { text, encodingNote } = await readCitationFile(file);
    const stored = await saveCitationFile({ name: file.name, kind, text, handle, encodingNote });
    return { name: file.name, kind, text, encodingNote, stored };
  } catch (_) {
    return null;
  }
}

// ==========================
//  Scratch (crash recovery)
// ==========================

export async function saveScratch(content, currentFile) {
  await idbSet('scratch', { content, current_file: currentFile });
}
export async function readScratch() {
  try { return await idbGet('scratch'); } catch (_) { return null; }
}
export async function clearScratch() {
  try { await idbDelete('scratch'); } catch (_) {}
}

// ==========================
//  Installed app: files opened from the OS, offline shell
// ==========================

// When the PWA is registered as a handler for .md files (manifest
// file_handlers), the OS hands them over through launchQueue.
export function initLaunchQueue(onFile, onFail) {
  const queue = window.launchQueue;
  if (!queue) return;
  queue.setConsumer(async (params) => {
    for (const handle of params.files || []) {
      try {
        const payload = await openHandle(handle);
        if (payload) onFile(payload);
      } catch (err) {
        if (onFail) onFail(err);
      }
    }
  });
}

export function registerServiceWorker(onUpdateReady) {
  if (!import.meta.env.PROD || !('serviceWorker' in navigator)) return;
  // Versioned URL: the CDN in front of the site caches .js for a year, so
  // a bare sw.js would keep serving the previous release's worker. A new
  // URL per version is a new cache key; same scope, so it replaces the
  // old registration.
  navigator.serviceWorker.register(`${import.meta.env.BASE_URL}sw.js?v=${encodeURIComponent(pkgVersion)}`).then((reg) => {
    reg.addEventListener('updatefound', () => {
      const worker = reg.installing;
      if (!worker) return;
      worker.addEventListener('statechange', () => {
        if (worker.state === 'installed' && navigator.serviceWorker.controller) onUpdateReady?.();
      });
    });
  }).catch(() => {});
}

// ==========================
//  Drag-and-drop to open
// ==========================

export function initDragDrop(onFile, onFail, onCitationFile) {
  document.addEventListener('dragover', (e) => e.preventDefault());
  document.addEventListener('drop', async (e) => {
    e.preventDefault(); // otherwise the browser navigates the tab to the file
    const item = e.dataTransfer?.items?.[0];
    try {
      const first = e.dataTransfer?.files?.[0];
      // A .bib or .csl file goes to the citation store. A document keeps its path.
      if (first && citationKind(first.name) && onCitationFile) {
        const kind = /** @type {'bib'|'csl'} */ (citationKind(first.name));
        /** @type {any} */
        let handle = null;
        if (item?.kind === 'file' && item.getAsFileSystemHandle) {
          try { handle = await item.getAsFileSystemHandle(); } catch (_) {}
          if (handle && handle.kind !== 'file') handle = null;
        }
        const { text, encodingNote } = await readCitationFile(handle ? await handle.getFile() : first);
        const stored = await saveCitationFile({ name: first.name, kind, text, handle, encodingNote });
        onCitationFile({ name: first.name, kind, text, encodingNote, stored });
        return;
      }
      if (item?.kind === 'file' && item.getAsFileSystemHandle) {
        const payload = await openHandle(await item.getAsFileSystemHandle());
        if (payload) onFile(payload);
        return;
      }
      const file = first;
      if (!file || !OPENABLE.test(file.name)) return;
      currentFileHandle = null;
      onFile({ path: file.name, content: await file.text() });
    } catch (err) { if (onFail) onFail(err); }
  });
}
