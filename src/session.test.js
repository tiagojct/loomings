import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { createSession } from './session.js';

function makeSession(overrides = {}) {
  const calls = { dirty: 0, clean: 0, saved: [], errors: [], written: [], scratch: [], cleared: 0 };
  let text = 'first draft';
  let home = { file: 'notes.md', docId: null };

  const session = createSession({
    content: () => text,
    target: () => home,
    write: overrides.write || (async (value) => { calls.written.push(value); }),
    storage: {
      saveScratch: overrides.saveScratch || (async (value) => { calls.scratch.push(value); }),
      clearScratch: overrides.clearScratch || (async () => { calls.cleared++; }),
    },
    onDirty: () => calls.dirty++,
    onClean: () => calls.clean++,
    onSaved: (value) => calls.saved.push(value),
    onError: (message) => calls.errors.push(message),
  });

  return {
    session, calls,
    setText: (value) => { text = value; },
    setHome: (value) => { home = value; },
  };
}

describe('document session', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it('flags the buffer dirty once and clean again after a save', async () => {
    const { session, calls } = makeSession();

    session.markEdited();
    session.markEdited();
    expect(calls.dirty).toBe(1);
    expect(session.isDirty()).toBe(true);

    expect(await session.saveNow()).toBe(true);
    expect(calls.clean).toBe(1);
    expect(calls.saved).toEqual(['first draft']);
    expect(calls.written).toEqual(['first draft']);
    expect(session.isDirty()).toBe(false);
    expect(calls.cleared).toBeGreaterThan(0);
  });

  it('debounces the draft write and stores the latest text', async () => {
    const { session, calls, setText } = makeSession();

    session.markEdited();
    setText('second draft');
    await vi.advanceTimersByTimeAsync(799);
    expect(calls.scratch).toEqual([]);

    await vi.advanceTimersByTimeAsync(1);
    expect(calls.scratch).toEqual(['second draft']);
  });

  it('autosaves to the home after two seconds, but only when it has one', async () => {
    const { session, calls, setHome } = makeSession();

    session.markEdited();
    await vi.advanceTimersByTimeAsync(2000);
    expect(calls.written).toEqual(['first draft']);

    setHome({ file: null, docId: null });
    session.markEdited();
    await vi.advanceTimersByTimeAsync(2000);
    expect(calls.written).toHaveLength(1);
  });

  it('reports a draft that could not be stored instead of throwing', async () => {
    const { session, calls } = makeSession({
      saveScratch: async () => { throw new Error('quota exceeded'); },
    });

    session.markEdited();
    await vi.advanceTimersByTimeAsync(800);

    expect(calls.errors).toHaveLength(1);
    expect(calls.errors[0]).toMatch(/Draft not kept: quota exceeded/);
  });

  it('retries a draft write that failed instead of believing it landed', async () => {
    let attempts = 0;
    const { session, calls } = makeSession({
      saveScratch: async (value) => {
        attempts++;
        if (attempts === 1) throw new Error('transient');
        calls.scratch.push(value);
      },
    });

    session.markEdited();
    await vi.advanceTimersByTimeAsync(800);
    expect(attempts).toBe(1);

    await session.flushScratch();
    expect(attempts).toBe(2);
    expect(calls.scratch).toEqual(['first draft']);
  });

  it('stays dirty and reports when the save itself fails', async () => {
    const { session, calls } = makeSession({
      write: async () => { throw new Error('disk full'); },
    });

    session.markEdited();
    expect(await session.saveNow()).toBe(false);
    expect(calls.errors[0]).toMatch(/Save failed: disk full/);
    expect(session.isDirty()).toBe(true);
    expect(calls.clean).toBe(0);
  });

  it('serialises overlapping saves', async () => {
    const pending = [];
    const { session, calls } = makeSession({
      write: (value) => new Promise((resolve) => { calls.written.push(value); pending.push(resolve); }),
    });

    const first = session.saveNow();
    const second = session.saveNow();
    expect(calls.written).toHaveLength(1);

    pending.shift()();
    await first;
    await Promise.resolve();
    expect(calls.written).toHaveLength(2);

    pending.shift()();
    await second;
  });

  it('stays dirty when the buffer changed while the save was in flight', async () => {
    let finish;
    const { session, calls, setText } = makeSession({
      write: () => new Promise((resolve) => { finish = resolve; }),
    });

    session.markEdited();
    const saving = session.saveNow();

    // The write is in flight (a slow disk, a permission re-prompt) and the
    // user keeps typing: that text is not in what is being written.
    setText('edited during the save');
    session.markEdited();
    finish();
    await saving;

    expect(session.isDirty()).toBe(true);
    expect(calls.clean).toBe(0);
    expect(calls.cleared).toBe(0);
  });

  it('does not touch the new buffer when a save lands after a repoint', async () => {
    let finish;
    const { session, calls } = makeSession({
      write: () => new Promise((resolve) => { finish = resolve; }),
    });

    session.markEdited();
    const saving = session.saveNow();
    session.repoint(); // New / Open / reload: the buffer moved on
    finish();

    expect(await saving).toBe(true);
    expect(calls.saved).toEqual([]);
    expect(calls.errors).toEqual([]);
    expect(session.isDirty()).toBe(false);
  });

  it('waits for a draft still in flight before clearing it', async () => {
    let finish;
    const { session, calls } = makeSession({
      saveScratch: () => new Promise((resolve) => { finish = resolve; }),
    });

    session.markEdited();
    await vi.advanceTimersByTimeAsync(800); // the write starts and hangs
    const discarding = session.discardScratch();
    finish();
    await discarding;

    expect(calls.cleared).toBeGreaterThan(0);
  });

  it('flushes the draft immediately without waiting for the debounce', async () => {
    const { session, calls } = makeSession();

    session.markEdited();
    await session.flushScratch();
    expect(calls.scratch).toEqual(['first draft']);
  });

  it('cancels pending work when the buffer is cleaned', async () => {
    const { session, calls } = makeSession();

    session.markEdited();
    session.markClean();
    await vi.advanceTimersByTimeAsync(3000);

    expect(calls.scratch).toEqual([]);
    expect(calls.written).toEqual([]);
    expect(session.isDirty()).toBe(false);
  });
});
