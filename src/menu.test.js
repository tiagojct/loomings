import { describe, it, expect, beforeEach } from 'vitest';
import { Window } from 'happy-dom';
import { attachMenu, closeAllMenus } from './menu.js';

describe('accessible toolbar menu', () => {
  let window;
  let document;
  let btn;
  let menuEl;

  beforeEach(() => {
    window = new Window();
    document = window.document;
    globalThis.document = document;
    globalThis.window = window;

    btn = document.createElement('button');
    btn.id = 'test-btn';
    btn.textContent = 'Menu';

    menuEl = document.createElement('div');
    menuEl.id = 'test-menu';
    menuEl.className = 'tb-menu hidden';
    menuEl.innerHTML = `
      <button class="tb-menu-item" data-action="one">Item 1</button>
      <button class="tb-menu-item on" data-action="two">Item 2</button>
      <button class="tb-menu-item" data-action="three">Item 3</button>
    `;

    document.body.appendChild(btn);
    document.body.appendChild(menuEl);
  });

  it('opens and closes on button click, setting aria-expanded properly', () => {
    attachMenu(btn, menuEl);

    expect(menuEl.classList.contains('hidden')).toBe(true);
    expect(btn.getAttribute('aria-expanded')).toBeNull();

    // Click to open
    btn.click();
    expect(menuEl.classList.contains('hidden')).toBe(false);
    expect(btn.getAttribute('aria-expanded')).toBe('true');

    // Click to close
    btn.click();
    expect(menuEl.classList.contains('hidden')).toBe(true);
    expect(btn.getAttribute('aria-expanded')).toBe('false');
  });

  it('triggers onPick with the chosen item and closes the menu', () => {
    let picked = null;
    attachMenu(btn, menuEl, {
      onPick: (item) => { picked = item.dataset.action; },
    });

    btn.click();
    const item1 = menuEl.querySelector('[data-action="one"]');
    item1.click();

    expect(picked).toBe('one');
    expect(menuEl.classList.contains('hidden')).toBe(true);
    expect(btn.getAttribute('aria-expanded')).toBe('false');
  });

  it('closes all open menus when closeAllMenus is called', () => {
    attachMenu(btn, menuEl);
    btn.click();
    expect(menuEl.classList.contains('hidden')).toBe(false);

    closeAllMenus();
    expect(menuEl.classList.contains('hidden')).toBe(true);
  });

  it('skips items inside a collapsed section when roving with the arrow keys', () => {
    menuEl.innerHTML = `
      <button class="tb-menu-item" data-action="one">Item 1</button>
      <div class="tb-menu-section hidden">
        <button class="tb-menu-item" data-action="hidden">Recent file</button>
      </div>
      <button class="tb-menu-item" data-action="three">Item 3</button>
    `;
    attachMenu(btn, menuEl);
    btn.click();

    const down = () => menuEl.dispatchEvent(new window.KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true }));
    down(); // from no focus → first item
    expect(document.activeElement.dataset.action).toBe('one');

    down(); // the hidden item must not take focus
    expect(document.activeElement.dataset.action).toBe('three');
  });
});
