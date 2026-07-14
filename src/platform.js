// ========================================
// Loomings — platform seam
// Picks the Tauri or web implementation at runtime so editor.js never
// branches on it directly (except for UI that only makes sense on one
// side, e.g. the web toolbar, gated on the exported `isTauri` flag).
// ========================================

import * as tauriImpl from './platform-tauri.js';
import * as webImpl from './platform-web.js';

export const isTauri = '__TAURI_INTERNALS__' in window;
const impl = isTauri ? tauriImpl : webImpl;

export const {
  listen,
  getVersion,
  openUrl,
  ask,
  ipcSetTitle,
  ipcSaveFile,
  ipcSaveFileAs,
  ipcAddRecent,
  ipcSaveScratch,
  ipcReadScratch,
  ipcClearScratch,
  ipcConfirmQuit,
  ipcTakeLaunchFile,
  ipcFrontendReady,
  ipcWatchFile,
  ipcUnwatchFile,
  ipcSyncThemeMenu,
  ipcExportHtml,
  ipcOpenFile,
  ipcOpenExample,
  ipcCheckForUpdate,
  initTitlebarDrag,
  initDragDrop,
  // Web-only (undefined under Tauri — only called when !isTauri)
  getRecents,
  openRecent,
} = impl;
