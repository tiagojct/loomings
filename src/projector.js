// ========================================
// Loomings — classroom projector mode
// Large type in the editor and preview, the chrome hidden, the current line
// marked, and a caption naming the markup just used, so a room can follow.
// It sets effective values only and never writes a preference, so turning
// it off restores the writer's own settings exactly (as the native app).
// ========================================

export const PROJECTOR = Object.freeze({ editorFontSize: 28, previewFontSize: 26, columnWidth: 'wide' });

/**
 * The caption for a block marker typed at the start of a line, in the
 * native app's phrases, or null.
 *
 * @param {string} prefix the line's text up to the caret
 * @returns {string|null}
 */
export function markerName(prefix) {
  if (prefix === '```' || prefix === '~~~') return `Code block: ${prefix}`;
  if (!prefix.endsWith(' ')) return null;
  const mark = prefix.slice(0, -1);
  if (/^#{1,6}$/.test(mark)) return `Heading ${mark.length}: ${prefix}`;
  if (mark === '-' || mark === '*' || mark === '+') return `Bullet list: ${prefix}`;
  if (mark === '>') return `Quote: ${prefix}`;
  if (/^[0-9]+[.)]$/.test(mark)) return `Numbered list: ${prefix}`;
  return null;
}

/**
 * @param {{body: HTMLElement, apply: (on: boolean) => void}} options
 *   apply sets the effective sizes, width and current-line mark.
 */
export function createProjector({ body, apply }) {
  let on = false;
  return {
    get on() { return on; },
    /** @returns {boolean} the new state */
    toggle() {
      on = !on;
      body.classList.toggle('projector', on);
      apply(on);
      return on;
    },
  };
}
