import { describe, expect, it, vi } from 'vitest';
import { citedHtml } from './citations/document.js';
import { renderPreview } from './markdown.js';
import { createPreviewClient } from './preview-client.js';

function fakeWorker() {
  return {
    sent: [],
    onmessage: null,
    onerror: null,
    postMessage(message) {
      this.sent.push(message);
    },
    terminate: vi.fn(),
    answer(id, data) {
      this.onmessage?.({ data: { ...data, id } });
    },
  };
}

describe('preview client', () => {
  it('starts the worker only when the first render arrives', async () => {
    const worker = fakeWorker();
    const spawn = vi.fn(() => worker);
    const client = createPreviewClient({ spawn });

    expect(spawn).not.toHaveBeenCalled();
    const result = client.render('a', null);
    expect(spawn).toHaveBeenCalledTimes(1);
    expect(worker.sent.map((message) => message.source)).toEqual(['a']);

    worker.answer(worker.sent[0].id, { html: 'A' });
    await expect(result).resolves.toBe('A');
  });

  it('keeps one active request and replaces the pending request', async () => {
    const worker = fakeWorker();
    const client = createPreviewClient({ spawn: () => worker });
    const first = client.render('a', null);
    const second = client.render('b', null);
    const third = client.render('c', null);

    expect(worker.sent.map((message) => message.source)).toEqual(['a']);
    await expect(second).resolves.toBeNull();

    worker.answer(worker.sent[0].id, { html: 'A' });
    expect(worker.sent.map((message) => message.source)).toEqual(['a', 'c']);
    await expect(first).resolves.toBeNull();

    worker.answer(worker.sent[1].id, { html: 'C' });
    await expect(third).resolves.toBe('C');
  });

  it('ignores answers from an earlier active request', async () => {
    const worker = fakeWorker();
    const client = createPreviewClient({ spawn: () => worker });
    const first = client.render('a', null);
    const second = client.render('b', null);
    const firstId = worker.sent[0].id;

    worker.answer(firstId, { html: 'A' });
    await expect(first).resolves.toBeNull();
    expect(worker.sent.map((message) => message.source)).toEqual(['a', 'b']);

    worker.answer(firstId, { html: 'late A' });
    worker.answer(worker.sent[1].id, { html: 'B' });
    await expect(second).resolves.toBe('B');
  });

  it('uses the fallback when worker startup fails', async () => {
    const fallback = vi.fn((source) => `fallback: ${source}`);
    const client = createPreviewClient({
      spawn: () => {
        throw new Error('no worker');
      },
      fallback,
    });

    await expect(client.render('latest', null)).resolves.toBe('fallback: latest');
    expect(fallback).toHaveBeenCalledWith('latest', null);
  });

  it('falls back to the newest pending request after a runtime failure', async () => {
    const worker = fakeWorker();
    const fallback = vi.fn((source) => `fallback: ${source}`);
    const client = createPreviewClient({ spawn: () => worker, fallback });
    const active = client.render('a', null);
    const pending = client.render('b', null);
    const activeId = worker.sent[0].id;

    worker.onerror?.();

    expect(worker.terminate).toHaveBeenCalledTimes(1);
    await expect(active).resolves.toBeNull();
    await expect(pending).resolves.toBe('fallback: b');
    expect(fallback).toHaveBeenCalledTimes(1);
    expect(fallback).toHaveBeenCalledWith('b', null);

    worker.answer(activeId, { html: 'late A' });
    expect(fallback).toHaveBeenCalledTimes(1);
  });

  it('falls back to the pending request when postMessage throws', async () => {
    let client;
    /** @type {Promise<string|null>|undefined} */
    let pending;
    const worker = {
      onmessage: null,
      onerror: null,
      terminate: vi.fn(),
      postMessage(message) {
        pending = client.render('pending', null);
        throw new Error('cannot clone request');
      },
      answer(id, data) {
        this.onmessage?.({ data: { ...data, id } });
      },
    };
    const spawn = vi.fn(() => worker);
    const fallback = vi.fn((source) => `fallback: ${source}`);
    client = createPreviewClient({ spawn, fallback });

    const active = client.render('active', null);

    expect(worker.terminate).toHaveBeenCalledTimes(1);
    await expect(active).resolves.toBeNull();
    await expect(pending).resolves.toBe('fallback: pending');
    expect(fallback).toHaveBeenCalledTimes(1);
    expect(fallback).toHaveBeenCalledWith('pending', null);

    worker.answer(1, { html: 'late active result' });
    expect(fallback).toHaveBeenCalledTimes(1);
    await expect(client.render('later', null)).resolves.toBe('fallback: later');
    expect(spawn).toHaveBeenCalledTimes(1);
  });

  it('does not restart the worker after a lifecycle failure', async () => {
    const worker = fakeWorker();
    const spawn = vi.fn(() => worker);
    const fallback = vi.fn((source) => `fallback: ${source}`);
    const client = createPreviewClient({ spawn, fallback });
    const active = client.render('a', null);

    worker.onerror?.();
    await expect(active).resolves.toBe('fallback: a');
    await expect(client.render('b', null)).resolves.toBe('fallback: b');

    expect(spawn).toHaveBeenCalledTimes(1);
  });

  it('contains render errors without falling back or stopping the worker', async () => {
    const worker = fakeWorker();
    const fallback = vi.fn(() => 'fallback');
    const client = createPreviewClient({ spawn: () => worker, fallback });
    const request = client.render('bad', null);

    worker.answer(worker.sent[0].id, { error: 'bad render' });

    await expect(request).resolves.toBeNull();
    expect(fallback).not.toHaveBeenCalled();
    expect(worker.terminate).not.toHaveBeenCalled();
  });

  it('resolves active and pending requests when reset terminates the worker', async () => {
    const worker = fakeWorker();
    const client = createPreviewClient({ spawn: () => worker });
    const active = client.render('a', null);
    const pending = client.render('b', null);

    client.reset();

    await expect(active).resolves.toBeNull();
    await expect(pending).resolves.toBeNull();
    expect(worker.terminate).toHaveBeenCalledTimes(1);
  });

  it('uses citation-aware preview rendering as the default fallback', async () => {
    const client = createPreviewClient({
      spawn: () => {
        throw new Error('no worker');
      },
    });
    const source = '# Heading\n\n[@silva]';

    await expect(client.render(source, null)).resolves.toBe(citedHtml(source, null, renderPreview));
  });
});
