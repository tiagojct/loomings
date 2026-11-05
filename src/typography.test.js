import { describe, it, expect, vi } from 'vitest';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { smartTypography } from './typography.js';

function input(text, typed, flags = {}, on = true) {
  const state = EditorState.create({ extensions: smartTypography(() => on), doc: text });
  const [handler] = state.facet(EditorView.inputHandler);
  const dispatch = vi.fn();
  const view = /** @type {any} */ ({ state, dispatch, composing: false, compositionStarted: false, ...flags });
  const pos = text.length;
  const handled = handler(view, pos, pos, typed, () => state.update({}));
  return { handled, insert: dispatch.mock.calls[0]?.[0].changes.insert };
}

describe('smart typography', () => {
  it('curls quotes, joins dashes and dots', () => {
    expect(input('', '"').insert).toBe('“');
    expect(input('word', '"').insert).toBe('”');
    expect(input('(', '"').insert).toBe('“');
    expect(input('', "'").insert).toBe('‘');
    expect(input('word', "'").insert).toBe('’');
    expect(input('a-', '-').insert).toBe('—');
    expect(input('a..', '.').insert).toBe('…');
  });

  it('leaves other text and a switched-off editor alone', () => {
    expect(input('a', 'b').handled).toBe(false);
    expect(input('', '"', {}, false).handled).toBe(false);
  });

  it('rests during a composition', () => {
    expect(input('', "'", { composing: true }).handled).toBe(false);
    expect(input('', '"', { compositionStarted: true }).handled).toBe(false);
    expect(input('a-', '-', { composing: true }).handled).toBe(false);
  });
});
