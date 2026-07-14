// ========================================
// Loomings — Tauri platform adapter
// Implements the same contract as platform-web.js so editor.js never
// branches on runtime — see platform.js for the selection logic.
// ========================================

import { invoke } from '@tauri-apps/api/core';
import { listen as tauriListen } from '@tauri-apps/api/event';
import { getCurrentWindow } from '@tauri-apps/api/window';
import { getCurrentWebview } from '@tauri-apps/api/webview';
import { getVersion as tauriGetVersion } from '@tauri-apps/api/app';
import { ask as tauriAsk } from '@tauri-apps/plugin-dialog';
import { openUrl as tauriOpenUrl } from '@tauri-apps/plugin-opener';

export const listen = tauriListen;
export const getVersion = tauriGetVersion;
export const openUrl = tauriOpenUrl;
export const ask = tauriAsk;

export async function ipcSetTitle(title)         { try { await invoke('set_title', { title }); } catch (_) {} }
export async function ipcSaveFile(path, content) { return invoke('save_file', { path, content }); }
export async function ipcSaveFileAs(content)     { return invoke('save_file_as', { content }); }
export async function ipcAddRecent(filePath)     { try { await invoke('add_recent_file', { filePath }); } catch (_) {} }
export async function ipcSaveScratch(content, currentFile) {
  try { await invoke('save_scratch', { content, currentFile }); } catch (_) {}
}
export async function ipcReadScratch()  { try { return await invoke('read_scratch'); } catch (_) { return null; } }
export async function ipcClearScratch() { try { await invoke('clear_scratch'); } catch (_) {} }
export async function ipcConfirmQuit()  { return invoke('confirm_quit'); }
export async function ipcTakeLaunchFile() { try { return await invoke('take_launch_file'); } catch (_) { return null; } }
export async function ipcFrontendReady()  { try { await invoke('frontend_ready'); } catch (_) {} }
export async function ipcWatchFile(path, onFail) {
  // External-edit detection depends on this succeeding. If the OS denies
  // the watch (sandbox, permissions, network FS), surface it once so the
  // user knows reload-on-external-change is dead for this file.
  try { await invoke('watch_file', { path }); }
  catch (err) { if (onFail) onFail(err); }
}
export async function ipcUnwatchFile()  { try { await invoke('unwatch_file'); } catch (_) {} }
export async function ipcSyncThemeMenu(family) { try { await invoke('sync_theme_menu', { family }); } catch (_) {} }
export async function ipcExportHtml(content, suggestedName) { return invoke('export_html', { content, suggestedName }); }
export async function ipcOpenPath(path) { return invoke('open_path', { path }); }
export async function ipcCheckForUpdate() { try { return await invoke('check_for_update'); } catch (_) { return null; } }

// Native flow relies on Rust emitting 'file-opened' (menu-driven Open, or
// this dialog) rather than returning a payload directly — the caller's
// existing listen('file-opened', ...) subscription picks it up either way,
// so this intentionally returns null.
export async function ipcOpenFile() {
  try { await invoke('open_file_dialog'); } catch (_) {}
  return null;
}

// Same fire-and-forget-then-event pattern as ipcOpenFile.
export async function ipcOpenExample() {
  try { await invoke('open_example'); } catch (_) {}
  return null;
}

export function initTitlebarDrag(titlebar) {
  if (!titlebar) return;
  titlebar.addEventListener('mousedown', async (e) => {
    if (e.button !== 0) return;
    const win = getCurrentWindow();
    if (e.detail === 2) {
      try { await win.toggleMaximize(); } catch (_) {}
      return;
    }
    try { await win.startDragging(); } catch (_) {}
  });
}

// onFile is unused here — a native drop already flows through ipcOpenPath
// -> Rust emits 'file-opened' -> the caller's own listener handles it, same
// as any other open. Accepted for signature parity with the web adapter.
export function initDragDrop(onFile, onFail) {
  const OPENABLE = /\.(md|markdown|mdown|mkd|qmd|rmd|txt)$/i;
  getCurrentWebview().onDragDropEvent((e) => {
    if (e.payload.type !== 'drop' || !e.payload.paths?.length) return;
    const path = e.payload.paths.find((p) => OPENABLE.test(p));
    if (path) ipcOpenPath(path).catch((err) => { if (onFail) onFail(err); });
  }).catch(() => {});
}
