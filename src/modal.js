// ========================================
// Loomings — modal dialogs
// Focus enters the dialog, Tab cannot leave it, Escape closes it, and focus
// goes back to whatever opened it. The rest of the page is made inert, which
// also takes it out of the accessibility tree while the dialog is up.
// ========================================

const BACKGROUND = ['#web-toolbar', '#editor-container', '#statusbar'];

/** @param {HTMLElement} root @returns {HTMLElement[]} */
function focusables(root) {
  return Array.from(
    root.querySelectorAll('a[href], button:not([disabled]), input:not([disabled]), [tabindex]:not([tabindex="-1"])')
  );
}

/** @type {WeakMap<HTMLElement, {close: () => void}>} */
const openModals = new WeakMap();

/**
 * Opens a dialog element (its visibility is the app's `.hidden` class).
 *
 * @param {HTMLElement} dialog
 * @param {{opener?: HTMLElement|null, initialFocus?: HTMLElement|null}} [options]
 * @returns {{close: () => void}}
 */
export function openModal(dialog, { opener = null, initialFocus = null } = {}) {
  // Opening an already-open dialog (a habitual Cmd+P) must hand back the
  // controller that can actually close it, not a no-op that leaves the page
  // inert and the dialog on screen.
  const existing = openModals.get(dialog);
  if (existing) return existing;

  /** @type {HTMLElement[]} */
  const inerted = [];
  for (const selector of BACKGROUND) {
    const node = /** @type {HTMLElement|null} */ (document.querySelector(selector));
    if (node && !node.hasAttribute('inert')) inerted.push(node);
  }
  for (const node of inerted) node.setAttribute('inert', '');

  dialog.classList.remove('hidden');

  /** @param {KeyboardEvent} event */
  const onKeydown = (event) => {
    if (event.key === 'Escape') {
      event.preventDefault();
      event.stopPropagation();
      close();
      return;
    }
    if (event.key !== 'Tab') return;
    // `inert` already keeps focus out of the page behind in current browsers;
    // this keeps the cycle inside the dialog everywhere, and wraps at the ends.
    const items = focusables(dialog);
    if (items.length === 0) {
      event.preventDefault();
      dialog.focus();
      return;
    }
    const first = items[0];
    const last = items[items.length - 1];
    const active = /** @type {HTMLElement} */ (document.activeElement);
    // Shift+Tab from the first item — or from the dialog container, which is
    // focusable via tabindex="-1" but is not itself in the list — must wrap
    // to the end instead of walking out into browser chrome.
    if (event.shiftKey && items.indexOf(active) <= 0) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && active === last) {
      event.preventDefault();
      first.focus();
    }
  };

  dialog.addEventListener('keydown', onKeydown);

  const target = initialFocus || focusables(dialog)[0] || dialog;
  target.focus();

  function close() {
    openModals.delete(dialog);
    dialog.classList.add('hidden');
    dialog.removeEventListener('keydown', onKeydown);
    for (const node of inerted) node.removeAttribute('inert');
    if (opener && typeof opener.focus === 'function') opener.focus();
  }

  const controller = { close };
  openModals.set(dialog, controller);
  return controller;
}
