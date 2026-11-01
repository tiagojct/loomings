import { describe, it, expect } from 'vitest';
import { diff, addedWords, addedText } from './linediff.js';

const lines = (text) => text.split('\n');

/** Rebuilds the new lines from the ops, so any valid script passes. */
function apply(ops, old, next) {
  const out = [];
  for (const op of ops) {
    if (op.op === 'same') { expect(old[op.old]).toBe(next[op.new]); out.push(old[op.old]); }
    else if (op.op === 'added') out.push(next[op.new]);
  }
  return out;
}

describe('line differences (port of the native LineDiff)', () => {
  it('finds no change in identical texts', () => {
    expect(diff(['a', 'b', 'c'], ['a', 'b', 'c'])).toEqual([
      { op: 'same', old: 0, new: 0 }, { op: 'same', old: 1, new: 1 }, { op: 'same', old: 2, new: 2 },
    ]);
  });

  it('gives an insertion and a deletion in order', () => {
    expect(diff(lines('a\nb\nc\nd\ne'), lines('a\nc\nd\nx\ne'))).toEqual([
      { op: 'same', old: 0, new: 0 }, { op: 'removed', old: 1 }, { op: 'same', old: 2, new: 1 },
      { op: 'same', old: 3, new: 2 }, { op: 'added', new: 3 }, { op: 'same', old: 4, new: 4 },
    ]);
  });

  it('rebuilds the new text from any script, empty sides included', () => {
    for (const [a, b] of [['', 'a\nb'], ['a\nb', ''], ['x\ny\nz', 'z\ny\nx'], ['same', 'same'], ['a\nb\na\nb', 'b\na\nb\na']]) {
      expect(apply(diff(lines(a), lines(b)), lines(a), lines(b))).toEqual(lines(b));
    }
  });

  it('falls back on unrelated large texts without blowing up', () => {
    const old = Array.from({ length: 6000 }, (_, i) => `a${i}`);
    const next = Array.from({ length: 6000 }, (_, i) => `b${i}`);
    const ops = diff(old, next);
    expect(ops.length).toBe(12000);
    expect(apply(ops, old, next)).toEqual(next);
  });

  it('marks only the changed words inside a changed line', () => {
    expect(addedWords('The sea was calm today', 'The sea was wild today')).toEqual(['wild']);
  });

  it('keeps only what the new text adds', () => {
    expect(addedText('Write one two three.', 'Write one two thxree.')).toBe('thxree.');
    // "Done." became "Done": that word changed, so it counts; the new lines count whole.
    expect(addedText('Done.', 'Done\n\n- a\n- b')).toBe('Done\n\n- a\n- b');
    expect(addedText('a\nb', 'a\nb')).toBe('');
    expect(addedText('', 'new')).toBe('new');
  });
});
