// ========================================
// Loomings — browser adapter
// Everything that touches the browser's file, storage and window APIs:
// File System Access (Chromium) with input[type=file]/download fallback,
// IndexedDB for scratch/recents, document.title, window.confirm.
// editor.js never calls these APIs directly.
// ========================================

import exampleContent from '../examples/loomings.md?raw';
import { version as pkgVersion } from '../package.json';

export const hasFileSystemAccess = 'showOpenFilePicker' in window && 'showSaveFilePicker' in window;

const OPEN_TYPES = {
  description: 'Markdown',
  accept: { 'text/markdown': ['.md', '.markdown', '.mdown', '.mkd', '.qmd', '.rmd', '.txt'] },
};
const OPENABLE = /\.(md|markdown|mdown|mkd|qmd|rmd|txt)$/i;

// The handle behind the currently open file (Chromium only) — paired with
// editor.js's own `currentFile` display-string. Only this module reads or
// mutates it; editor.js never sees a FileSystemFileHandle directly.
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

function openDb() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, 1);
    req.onupgradeneeded = () => { req.result.createObjectStore(STORE); };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

export async function idbGet(key) {
  try {
    const db = await openDb();
    return await new Promise((resolve, reject) => {
      const tx = db.transaction(STORE, 'readonly');
      const req = tx.objectStore(STORE).get(key);
      req.onsuccess = () => resolve(req.result ?? null);
      req.onerror = () => reject(req.error);
    });
  } catch (_) { return null; }
}

export async function idbSet(key, value) {
  try {
    const db = await openDb();
    await new Promise((resolve, reject) => {
      const tx = db.transaction(STORE, 'readwrite');
      tx.objectStore(STORE).put(value, key);
      tx.oncomplete = resolve;
      tx.onerror = () => reject(tx.error);
    });
  } catch (_) {}
}

export async function idbDelete(key) {
  try {
    const db = await openDb();
    await new Promise((resolve, reject) => {
      const tx = db.transaction(STORE, 'readwrite');
      tx.objectStore(STORE).delete(key);
      tx.oncomplete = resolve;
      tx.onerror = () => reject(tx.error);
    });
  } catch (_) {}
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
  document.title = title ? `${title} — Loomings` : 'Loomings';
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
    } catch (_) { return null; } // user cancelled
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
    } catch (_) { return null; } // user cancelled
    const file = await handle.getFile();
    currentFileHandle = handle;
    return { path: file.name, content: await file.text() };
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
  currentFileHandle = handle;
  return { path: file.name, content: await file.text() };
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
  const recents = (await idbGet('recents')) || [];
  const next = [
    { name: filePath, handle: currentFileHandle, lastOpened: Date.now() },
    ...recents.filter((r) => r.name !== filePath),
  ].slice(0, 10);
  await idbSet('recents', next);
}

export async function getRecents() { return (await idbGet('recents')) || []; }

// Reconnects a stored recent — requestPermission needs the click that
// triggered this call, so callers must invoke it directly from a click
// handler, not after an intervening await.
export async function openRecent(entry) {
  const granted = await entry.handle.requestPermission({ mode: 'readwrite' });
  if (granted !== 'granted') {
    const recents = (await idbGet('recents')) || [];
    await idbSet('recents', recents.filter((r) => r.name !== entry.name));
    return null;
  }
  const file = await entry.handle.getFile();
  currentFileHandle = entry.handle;
  return { path: file.name, content: await file.text() };
}

// ==========================
//  Scratch (crash recovery)
// ==========================

export async function saveScratch(content, currentFile) {
  await idbSet('scratch', { content, current_file: currentFile });
}
export async function readScratch() { return idbGet('scratch'); }
export async function clearScratch() { return idbDelete('scratch'); }

// ==========================
//  Drag-and-drop to open
// ==========================

export function initDragDrop(onFile, onFail) {
  document.addEventListener('dragover', (e) => e.preventDefault());
  document.addEventListener('drop', async (e) => {
    e.preventDefault(); // otherwise the browser navigates the tab to the file
    const item = e.dataTransfer?.items?.[0];
    try {
      if (item?.kind === 'file' && item.getAsFileSystemHandle) {
        const payload = await openHandle(await item.getAsFileSystemHandle());
        if (payload) onFile(payload);
        return;
      }
      const file = e.dataTransfer?.files?.[0];
      if (!file || !OPENABLE.test(file.name)) return;
      currentFileHandle = null;
      onFile({ path: file.name, content: await file.text() });
    } catch (err) { if (onFail) onFail(err); }
  });
}
