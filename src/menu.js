// ========================================
// Loomings — accessible toolbar popover menus
// Full keyboard navigation support (ArrowDown, ArrowUp, Home, End, Escape).
// ========================================

const openMenus = new Set();

/** @returns {boolean} */
export function hasOpenMenus() { return openMenus.size > 0; }

export function closeAllMenus() {
  for (const close of [...openMenus]) close();
}

if (typeof document !== 'undefined') {
  document.addEventListener('click', closeAllMenus);
}

/**
 * Attaches popover menu behavior to a trigger button and menu container.
 *
 * @param {HTMLElement} btn
 * @param {HTMLElement} menuEl
 * @param {object} [options]
 * @param {() => void} [options.onOpen]
 * @param {(item: HTMLElement, target: HTMLElement) => void} [options.onPick]
 * @returns {{ close: (restoreFocus?: boolean) => void }}
 */
export function attachMenu(btn, menuEl, { onOpen, onPick } = {}) {
  if (!btn || !menuEl) return { close() {} };

  // A menu can hold collapsed sections (the documents menu's "Recent files");
  // an item inside one is not focusable, so roving arrow navigation must skip
  // it or the focus ring appears to stall.
  const isVisible = (item) => !item.hidden && !item.closest('.hidden') && !item.closest('[hidden]');
  /** @returns {HTMLElement[]} */
  const getMenuItems = () =>
    /** @type {HTMLElement[]} */ (Array.from(menuEl.querySelectorAll('.tb-menu-item:not([disabled])'))).filter(isVisible);

  const open = (focusFirst = false) => {
    closeAllMenus();
    onOpen?.();
    menuEl.classList.remove('hidden');
    btn.setAttribute('aria-expanded', 'true');
    openMenus.add(close);
    if (focusFirst) {
      const items = getMenuItems();
      const active = items.find((it) => it.classList.contains('on')) || items[0];
      active?.focus();
    }
  };

  const close = (restoreFocus = false) => {
    if (menuEl.classList.contains('hidden')) return;
    menuEl.classList.add('hidden');
    btn.setAttribute('aria-expanded', 'false');
    openMenus.delete(close);
    if (restoreFocus) btn.focus();
  };

  btn.addEventListener('click', (e) => {
    e.stopPropagation();
    menuEl.classList.contains('hidden') ? open(false) : close(false);
  });

  btn.addEventListener('keydown', (e) => {
    if (e.key === 'ArrowDown' || e.key === 'Enter' || e.key === ' ') {
      if (menuEl.classList.contains('hidden')) {
        e.preventDefault();
        open(true);
      }
    }
  });

  menuEl.addEventListener('click', (e) => {
    e.stopPropagation();
    const target = /** @type {HTMLElement} */ (e.target);
    const item = target.closest('.tb-menu-item');
    if (!item) return;
    close(true);
    onPick?.(/** @type {HTMLElement} */ (item), target);
  });

  menuEl.addEventListener('keydown', (e) => {
    const items = getMenuItems();
    if (!items.length) return;
    const currentIdx = items.indexOf(/** @type {HTMLElement} */ (document.activeElement));

    if (e.key === 'ArrowDown') {
      e.preventDefault();
      const nextIdx = currentIdx < items.length - 1 ? currentIdx + 1 : 0;
      items[nextIdx]?.focus();
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      const prevIdx = currentIdx > 0 ? currentIdx - 1 : items.length - 1;
      items[prevIdx]?.focus();
    } else if (e.key === 'Home') {
      e.preventDefault();
      items[0]?.focus();
    } else if (e.key === 'End') {
      e.preventDefault();
      items[items.length - 1]?.focus();
    } else if (e.key === 'Escape') {
      e.preventDefault();
      close(true);
    } else if (e.key === 'Tab') {
      close(false);
    }
  });

  return { close };
}
