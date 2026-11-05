// A URL pasted over selected words makes a link. The rule is shared with the
// native editor (PasteLink): macos/Tests/LoomingsEditorTests/Fixtures/paste-links.json
// is the contract, and a change goes into that fixture first.

const URL_ONLY = /^(?:https?:\/\/|mailto:)\S+$/i;
// The selection is already the destination of a link, or it is in code.
const INSIDE_DESTINATION = /(?:\]\(|\]:\s*|<)$/;

/**
 * @param {string} selected the selected text
 * @param {string} pasted the text on the clipboard
 * @param {string} before the text between the line start and the selection
 * @returns {string | null} the text to insert, or null for an ordinary paste
 */
export function linkFromPaste(selected, pasted, before = '') {
  const url = pasted.trim();
  const label = selected.trim();
  if (!label || !URL_ONLY.test(url) || /[<>]/.test(url)) return null;
  if (/[\n\r[\]]/.test(selected) || URL_ONLY.test(label)) return null;
  if (INSIDE_DESTINATION.test(before)) return null;
  if ((before.match(/`/g)?.length ?? 0) % 2 === 1) return null;

  const start = selected.indexOf(label);
  const destination = /[()]/.test(url) ? `<${url}>` : url;
  return `${selected.slice(0, start)}[${label}](${destination})${selected.slice(start + label.length)}`;
}
