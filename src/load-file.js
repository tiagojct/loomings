import { adoptFileHandle, forgetFile } from './browser.js';

/**
 * @typedef {{
 *   dirty: boolean,
 *   confirmDiscard: (prompt: string) => Promise<boolean>,
 *   discardScratch: () => Promise<void>,
 *   applyContent: () => Promise<void>,
 *   finishLoad: () => Promise<void>,
 * }} LoadFilePorts
 */

/**
 * Confirm and complete a document load, including its active save target.
 * @param {{path?: string, handle?: FileSystemFileHandle|null}} payload
 * @param {LoadFilePorts} ports
 * @returns {Promise<boolean>}
 */
export async function loadFileAfterConfirmation(payload, ports) {
  if (ports.dirty && !(await ports.confirmDiscard('Open new file?'))) return false;
  await ports.discardScratch();
  await ports.applyContent();
  if (payload.path) adoptFileHandle(payload.handle ?? null);
  else forgetFile();
  await ports.finishLoad();
  return true;
}
