import { describe, it, expect, vi } from 'vitest';
import { Window } from 'happy-dom';
import { readFileSync } from 'node:fs';
import { markerName, createProjector, PROJECTOR } from './projector.js';

describe('projector captions', () => {
  it('names a block marker just typed, in the native phrases', () => {
    expect(markerName('## ')).toBe('Heading 2: ## ');
    expect(markerName('# ')).toBe('Heading 1: # ');
    expect(markerName('###### ')).toBe('Heading 6: ###### ');
    expect(markerName('- ')).toBe('Bullet list: - ');
    expect(markerName('* ')).toBe('Bullet list: * ');
    expect(markerName('+ ')).toBe('Bullet list: + ');
    expect(markerName('> ')).toBe('Quote: > ');
    expect(markerName('1. ')).toBe('Numbered list: 1. ');
    expect(markerName('12) ')).toBe('Numbered list: 12) ');
    expect(markerName('```')).toBe('Code block: ```');
    expect(markerName('~~~')).toBe('Code block: ~~~');
  });

  it('names nothing else', () => {
    for (const prefix of ['##', '####### ', 'a ', '. ', ') ', '-', '1.', 'x1. ', '``', '']) {
      expect(markerName(prefix), JSON.stringify(prefix)).toBeNull();
    }
  });
});

describe('projector mode', () => {
  it('sets the projector sizes', () => {
    expect(PROJECTOR).toEqual({ editorFontSize: 28, previewFontSize: 26, columnWidth: 'wide' });
  });

  it('toggles body.projector and the effective values, and writes nothing to storage', () => {
    const window = new Window();
    const setItem = vi.spyOn(window.localStorage, 'setItem');
    const apply = vi.fn();
    const projector = createProjector({ body: window.document.body, apply });
    expect(projector.on).toBe(false);
    expect(projector.toggle()).toBe(true);
    expect(window.document.body.classList.contains('projector')).toBe(true);
    expect(apply).toHaveBeenLastCalledWith(true);
    expect(projector.toggle()).toBe(false);
    expect(window.document.body.classList.contains('projector')).toBe(false);
    expect(apply).toHaveBeenLastCalledWith(false);
    expect(setItem).not.toHaveBeenCalled();
  });

  it('hides the chrome and enlarges the preview in the stylesheet', () => {
    const css = readFileSync(new URL('./style.css', import.meta.url), 'utf8');
    expect(css).toMatch(/body\.projector #statusbar[^{]*\{[^}]*display:\s*none/);
    expect(css).toMatch(/body\.projector \.masthead[^{]*\{[^}]*display:\s*none/);
    expect(css).toMatch(/body\.projector #preview\s*\{[^}]*font-size:\s*26px/);
  });
});
