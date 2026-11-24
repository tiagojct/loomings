/**
 * Confirm before replacing the current document.
 * @param {boolean} dirty
 * @param {(prompt: string) => Promise<boolean>} confirmDiscard
 * @param {() => Promise<void>} load
 * @returns {Promise<boolean>}
 */
export async function loadFileAfterConfirmation(dirty, confirmDiscard, load) {
  if (dirty && !(await confirmDiscard('Open new file?'))) return false;
  await load();
  return true;
}
