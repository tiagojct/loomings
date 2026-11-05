import { describe, it, expect, beforeEach } from 'vitest';
import { Window } from 'happy-dom';
import { openModal } from './modal.js';

describe('modal dialog', () => {
  let window;
  let document;
  let opener;
  let dialog;
  let first;
  let last;
  let background;

  beforeEach(() => {
    window = new Window();
    document = window.document;
    globalThis.document = document;
    globalThis.window = window;
    globalThis.HTMLElement = window.HTMLElement;

    background = document.createElement('div');
    background.id = 'web-toolbar';
    opener = document.createElement('button');
    opener.textContent = 'About';
    background.appendChild(opener);

    dialog = document.createElement('div');
    dialog.id = 'about';
    dialog.className = 'hidden';
    dialog.innerHTML = `
      <div id="about-inner" tabindex="-1">
        <a href="#" id="one">one</a>
        <a href="#" id="two">two</a>
      </div>`;
    document.body.append(background, dialog);
    first = dialog.querySelector('#one');
    last = dialog.querySelector('#two');
    opener.focus();
  });

  it('shows the dialog, moves focus inside and makes the page behind inert', () => {
    openModal(dialog);

    expect(dialog.classList.contains('hidden')).toBe(false);
    expect(dialog.contains(document.activeElement)).toBe(true);
    expect(background.hasAttribute('inert')).toBe(true);
  });

  it('keeps Tab inside, wrapping at both ends', () => {
    openModal(dialog);
    const tab = (shiftKey = false) =>
      document.activeElement.dispatchEvent(
        new window.KeyboardEvent('keydown', { key: 'Tab', shiftKey, bubbles: true, cancelable: true })
      );

    last.focus();
    tab();
    expect(document.activeElement).toBe(first);

    first.focus();
    tab(true);
    expect(document.activeElement).toBe(last);
  });

  it('closes on Escape and gives focus back to the opener', () => {
    openModal(dialog, { opener });
    last.focus();

    document.activeElement.dispatchEvent(
      new window.KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true })
    );

    expect(dialog.classList.contains('hidden')).toBe(true);
    expect(background.hasAttribute('inert')).toBe(false);
    expect(document.activeElement).toBe(opener);
  });

  it('can be opened twice and still closes once', () => {
    const first = openModal(dialog);
    const second = openModal(dialog); // Cmd+P pressed again while it is open
    expect(second).toBe(first);

    second.close();
    expect(dialog.classList.contains('hidden')).toBe(true);
    expect(background.hasAttribute('inert')).toBe(false);
  });

  it('wraps to the last item when Shift+Tab starts from a non-focusable container', () => {
    const container = dialog.querySelector('#about-inner');
    openModal(dialog, { initialFocus: container });
    expect(document.activeElement).toBe(container);

    const evt = new window.KeyboardEvent('keydown', { key: 'Tab', shiftKey: true, bubbles: true, cancelable: true });
    container.dispatchEvent(evt);

    expect(evt.defaultPrevented).toBe(true);
    expect(document.activeElement).toBe(last);
  });

  it('restores the page when closed programmatically', () => {
    const modal = openModal(dialog, { opener });
    modal.close();

    expect(dialog.classList.contains('hidden')).toBe(true);
    expect(background.hasAttribute('inert')).toBe(false);
    expect(document.activeElement).toBe(opener);
  });

  it('runs onClose after each kind of close', () => {
    let closed = 0;
    openModal(dialog, { opener, onClose: () => { closed++; } });
    dialog.dispatchEvent(new window.KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
    expect(closed).toBe(1);
    openModal(dialog, { opener, onClose: () => { closed++; } }).close();
    expect(closed).toBe(2);
  });

  it('leaves hidden items out of the Tab cycle', () => {
    const hidden = document.createElement('div');
    hidden.className = 'hidden';
    hidden.innerHTML = '<button>Hidden</button>';
    dialog.appendChild(hidden);
    openModal(dialog, { opener });
    last.focus();
    dialog.dispatchEvent(new window.KeyboardEvent('keydown', { key: 'Tab', bubbles: true, cancelable: true }));
    expect(document.activeElement).toBe(first);
  });
});
