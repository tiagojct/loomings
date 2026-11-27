import { describe, expect, it, vi } from 'vitest';
import { createPreviewLifecycle } from './preview-lifecycle.js';

function deferred() {
  /** @type {(value?: any) => void} */
  let resolve;
  const promise = new Promise((done) => { resolve = done; });
  return { promise, resolve };
}

const prepare = (source, switched = false) => () => ({
  source,
  report: null,
  switched,
});

function makeLifecycle(options = {}) {
  return createPreviewLifecycle({
    render: options.render ?? vi.fn(async (source) => source),
    isShown: options.isShown ?? (() => true),
    apply: options.apply ?? vi.fn(),
    hasDiagrams: options.hasDiagrams ?? (() => true),
    renderDiagrams: options.renderDiagrams ?? vi.fn(async () => {}),
    afterDiagrams: options.afterDiagrams ?? vi.fn(),
  });
}

describe('preview lifecycle', () => {
  it('keeps a handout visible when an earlier worker result arrives during print rendering', async () => {
    const worker = deferred();
    const printDiagrams = deferred();
    let visible = 'previous preview';
    const render = vi.fn()
      .mockReturnValueOnce(worker.promise)
      .mockResolvedValueOnce('refreshed preview');
    const lifecycle = makeLifecycle({
      render,
      apply: (html) => { visible = html; },
      hasDiagrams: () => false,
    });
    const pendingPreview = lifecycle.update({ prepare: prepare('draft') });

    lifecycle.beginPrint();
    visible = 'handout';
    const printBuild = printDiagrams.promise;
    const prepareDuringPrint = vi.fn(prepare('later'));
    const ignoredDuringPrint = lifecycle.update({ prepare: prepareDuringPrint });

    await ignoredDuringPrint;
    expect(prepareDuringPrint).not.toHaveBeenCalled();
    expect(render).toHaveBeenCalledTimes(1);
    worker.resolve('late live preview');
    await pendingPreview;
    expect(visible).toBe('handout');

    printDiagrams.resolve();
    await printBuild;
    lifecycle.endPrint();
    await lifecycle.update({ prepare: prepare('draft') });

    expect(visible).toBe('refreshed preview');
    expect(render).toHaveBeenCalledTimes(2);
  });

  it('keeps diagram synchronization current when a citation render returns identical HTML', async () => {
    const diagrams = deferred();
    const afterDiagrams = vi.fn();
    const apply = vi.fn();
    const lifecycle = makeLifecycle({
      render: vi.fn(async () => 'visible HTML'),
      apply,
      renderDiagrams: () => diagrams.promise,
      afterDiagrams,
    });
    const visibleRender = lifecycle.update({ prepare: prepare('visible') });
    await Promise.resolve();
    await lifecycle.update({
      prepare: prepare('citation update'),
      onlyIfChanged: true,
    });

    diagrams.resolve();
    await visibleRender;

    expect(afterDiagrams).toHaveBeenCalledTimes(1);
    expect(apply).toHaveBeenCalledTimes(1);
  });

  it('keeps diagram synchronization current when a newer render returns null', async () => {
    const diagrams = deferred();
    const afterDiagrams = vi.fn();
    const apply = vi.fn();
    const render = vi.fn()
      .mockResolvedValueOnce('visible HTML')
      .mockResolvedValueOnce(null);
    const lifecycle = makeLifecycle({
      render,
      apply,
      renderDiagrams: () => diagrams.promise,
      afterDiagrams,
    });
    const visibleRender = lifecycle.update({ prepare: prepare('visible') });
    await Promise.resolve();
    await lifecycle.update({ prepare: prepare('failed update') });

    diagrams.resolve();
    await visibleRender;

    expect(afterDiagrams).toHaveBeenCalledTimes(1);
    expect(apply).toHaveBeenCalledTimes(1);
  });

  it('does not synchronize diagrams after newer content replaces them', async () => {
    const oldDiagrams = deferred();
    const newDiagrams = deferred();
    const afterDiagrams = vi.fn();
    const renderDiagrams = vi.fn()
      .mockReturnValueOnce(oldDiagrams.promise)
      .mockReturnValueOnce(newDiagrams.promise);
    const lifecycle = makeLifecycle({
      renderDiagrams,
      afterDiagrams,
    });
    const oldContent = lifecycle.update({ prepare: prepare('old') });
    await Promise.resolve();
    const newContent = lifecycle.update({ prepare: prepare('new') });
    await Promise.resolve();

    oldDiagrams.resolve();
    await oldContent;
    expect(afterDiagrams).not.toHaveBeenCalled();

    newDiagrams.resolve();
    await newContent;
    expect(afterDiagrams).toHaveBeenCalledTimes(1);
  });

  it('does not apply an older result after a newer request', async () => {
    const older = deferred();
    const current = deferred();
    const apply = vi.fn();
    const render = vi.fn((source) => source === 'older' ? older.promise : current.promise);
    const lifecycle = makeLifecycle({
      render,
      apply,
      hasDiagrams: () => false,
    });
    const oldUpdate = lifecycle.update({ prepare: prepare('older') });
    const currentUpdate = lifecycle.update({ prepare: prepare('current') });

    current.resolve('current HTML');
    await currentUpdate;
    older.resolve('stale HTML');
    await oldUpdate;

    expect(apply).toHaveBeenCalledTimes(1);
    expect(apply).toHaveBeenCalledWith('current HTML');
  });
});
