// ========================================
// Loomings — Web platform adapter
// Implements the same contract as platform-tauri.js using browser-standard
// APIs: File System Access (Chromium) with input[type=file]/download
// fallback, IndexedDB for scratch/recents. See platform.js for selection.
// ========================================

import exampleContent from '../examples/loomings.md?raw';
import { version as pkgVersion } from '../package.json';

const hasFS = 'showOpenFilePicker' in window && 'showSaveFilePicker' in window;
const OPEN_TYPES = {
  description: 'Markdown',
  accept: { 'text/markdown': ['.md', '.markdown', '.mdown', '.mkd', '.qmd', '.rmd', '.txt'] },
};

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

async function idbGet(key) {
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

async function idbSet(key, value) {
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

async function idbDelete(key) {
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
//  Web-standard stand-ins for Tauri plugins
// ==========================

// Total no-op subscribe — matches Tauri's listen() shape (Promise<unlisten
// fn>) so registerListeners()'s Promise.all(...) in editor.js needs no
// changes, but nothing on web actually emits these events: every one of
// them already has a direct function call or keyboard shortcut on the web
// side (see the toolbar wiring / keydown handler in editor.js) instead of
// routing through the native-menu-driven event system.
export async function listen(_event, _cb) { return () => {}; }

export async function getVersion() { return pkgVersion; }

export async function openUrl(url) {
  window.open(url, '_blank', 'noopener,noreferrer');
}

export async function ask(message) {
  // Blunter than the native dialog (no title/kind styling, blocks the
  // main thread) but correct — a custom in-page modal is a nice-to-have,
  // not required for this to work.
  return window.confirm(message);
}

// ==========================
//  File I/O
// ==========================

export async function ipcSetTitle(title) {
  document.title = title ? `Loomings — ${title}` : 'Loomings';
}

export async function ipcSaveFile(path, content) {
  if (!currentFileHandle) return ipcSaveFileAs(content);
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

export async function ipcSaveFileAs(content) {
  if (hasFS) {
    let handle;
    try {
      handle = await window.showSaveFilePicker({ types: [OPEN_TYPES], suggestedName: 'untitled.md' });
    } catch (_) { return null; } // user cancelled
    const writable = await handle.createWritable();
    await writable.write(content);
    await writable.close();
    currentFileHandle = handle;
    return handle.name;
  }
  // No File System Access API (Firefox/Safari): a plain download, not an
  // in-place save. The caller surfaces this distinction to the user.
  downloadBlob(content, 'untitled.md', 'text/markdown');
  currentFileHandle = null;
  return null;
}

export async function ipcOpenFile() {
  if (hasFS) {
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

export async function ipcOpenExample() {
  currentFileHandle = null;
  return { path: '', content: exampleContent };
}

// A hosted web app is always latest on reload — there's nothing to check.
export async function ipcCheckForUpdate() { return null; }

export async function ipcExportHtml(content, suggestedName) {
  // Always a uniform download — a reusable Save handle doesn't help a
  // one-shot export, so there's no need to branch on FS Access here.
  downloadBlob(content, suggestedName, 'text/html');
  return suggestedName;
}

// FileSystemFileHandle is structured-cloneable (Chromium), so it goes into
// IndexedDB directly alongside its display metadata.
export async function ipcAddRecent(filePath) {
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

export async function ipcSaveScratch(content, currentFile) {
  await idbSet('scratch', { content, current_file: currentFile });
}
export async function ipcReadScratch() { return idbGet('scratch'); }
export async function ipcClearScratch() { return idbDelete('scratch'); }

// Explicit cuts for the web build — see the plan's "explicit cuts" list.
export async function ipcConfirmQuit()    {}
export async function ipcTakeLaunchFile() { return null; }
export async function ipcFrontendReady()  {}
export async function ipcWatchFile()      {} // no push file-change API on the web
export async function ipcUnwatchFile()    {}
export async function ipcSyncThemeMenu()  {} // no native menu to mirror into

export function initTitlebarDrag() {} // no window to drag in a browser tab

export function initDragDrop(onFile, onFail) {
  const OPENABLE = /\.(md|markdown|mdown|mkd|qmd|rmd|txt)$/i;
  document.addEventListener('dragover', (e) => e.preventDefault());
  document.addEventListener('drop', async (e) => {
    e.preventDefault(); // otherwise the browser navigates the tab to the file
    const item = e.dataTransfer?.items?.[0];
    try {
      if (item?.kind === 'file' && item.getAsFileSystemHandle) {
        const handle = await item.getAsFileSystemHandle();
        if (handle.kind !== 'file' || !OPENABLE.test(handle.name)) return;
        const file = await handle.getFile();
        currentFileHandle = handle;
        onFile({ path: file.name, content: await file.text() });
        return;
      }
      const file = e.dataTransfer?.files?.[0];
      if (!file || !OPENABLE.test(file.name)) return;
      currentFileHandle = null;
      onFile({ path: file.name, content: await file.text() });
    } catch (err) { if (onFail) onFail(err); }
  });
}
