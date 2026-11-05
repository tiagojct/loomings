import { describe, it, expect, vi } from 'vitest';
import { createCitationClient } from './client.js';

const report = (markdownSource) => ({ markdownSource });

function fakeWorker() {
  const w = { sent: [], onmessage: null, onerror: null, terminate: vi.fn() };
  w.postMessage = (m) => w.sent.push(m);
  w.answer = (id, r) => w.onmessage({ data: { id, report: r } });
  return w;
}
const fullSources = { bibs: [], styleXml: 's', localeXml: 'l', lang: 'en-US' };

describe('createCitationClient', () => {
  it('starts the worker on the first use only', () => {
    const spawn = vi.fn(fakeWorker);
    const client = createCitationClient({ spawn });
    expect(spawn).not.toHaveBeenCalled();
    client.update('a');
    client.update('b');
    expect(spawn).toHaveBeenCalledTimes(1);
  });
  it('drops older answers and keeps the latest', () => {
    const w = fakeWorker();
    const client = createCitationClient({ spawn: () => w });
    const seen = [];
    client.onReport((r) => seen.push(r));
    client.update('a');
    client.update('b');
    expect(w.sent.map((m) => m.type)).toEqual(['analyse', 'analyse']);
    w.answer(w.sent[1].id, report('b'));
    w.answer(w.sent[0].id, report('a'));
    expect(seen).toEqual([report('b')]);
    expect(client.latest()).toEqual(report('b'));
  });
  it('gives null before the first report', () => {
    expect(createCitationClient({ spawn: fakeWorker }).latest()).toBe(null);
  });
  it('sends the sources, then the last text again', async () => {
    const w = fakeWorker();
    const client = createCitationClient({ spawn: () => w });
    client.update('a');
    await client.setSources(fullSources);
    expect(w.sent.map((m) => m.type)).toEqual(['analyse', 'sources', 'analyse']);
    expect(w.sent[2].text).toBe('a');
    expect(w.sent[1].id).toBeLessThan(w.sent[2].id);
  });
  it('adds the en-US fallback for another language', async () => {
    const w = fakeWorker();
    const client = createCitationClient({ spawn: () => w });
    await client.setSources({ ...fullSources, lang: 'pt-PT' });
    expect(w.sent[0].sources.fallbackLocaleXml).toContain('<locale');
    expect(w.sent[0].sources.lang).toBe('pt-PT');
    expect(w.sent[0].sources.localeXml).toBe('l');
  });
  it('loads a locale that the sources do not carry', async () => {
    const w = fakeWorker();
    const client = createCitationClient({ spawn: () => w });
    await client.setSources({ bibs: [], styleXml: 's', lang: 'en-US' });
    expect(w.sent[0].sources.localeXml).toContain('xml:lang="en-US"');
    expect(w.sent[0].sources.fallbackLocaleXml).toBeUndefined();
  });
  it('sends only the newest sources when two calls overlap', async () => {
    const w = fakeWorker();
    const client = createCitationClient({ spawn: () => w });
    const first = client.setSources({ bibs: [], styleXml: 'one', lang: 'pt-PT' });
    const second = client.setSources({ bibs: [], styleXml: 'two', lang: 'es-ES' });
    await Promise.all([first, second]);
    expect(w.sent.filter((m) => m.type === 'sources').map((m) => m.sources.styleXml)).toEqual(['two']);
  });
  it('gives one note and literal text when the worker cannot start', () => {
    const client = createCitationClient({ spawn: () => { throw new Error('no worker'); } });
    const seen = [];
    client.onReport((r) => seen.push(r));
    client.update('a [@k]');
    expect(seen.length).toBe(1);
    expect(seen[0].citations).toEqual([]);
    expect(seen[0].bibliography).toEqual([]);
    expect(seen[0].markdownSource).toBe('a [@k]');
    expect(seen[0].notes).toEqual([{ from: 0, to: 0, line: 0, message: 'Citations are not available: the worker did not start.' }]);
    client.update('b');
    expect(seen[1].notes.length).toBe(1);
    expect(client.latest().markdownSource).toBe('b');
  });
  it('does not fail when sources arrive and the worker cannot start', async () => {
    const client = createCitationClient({ spawn: () => { throw new Error('no worker'); } });
    await client.setSources(fullSources);
    expect(client.latest()).toBe(null);
    client.update('a');
    expect(client.latest().notes.length).toBe(1);
  });
  it('gives the note when the worker fails later, and does not start it again', () => {
    const w = fakeWorker();
    const spawn = vi.fn(() => w);
    const client = createCitationClient({ spawn });
    client.update('a');
    w.onerror();
    expect(w.terminate).toHaveBeenCalled();
    expect(client.latest().notes.length).toBe(1);
    expect(client.latest().markdownSource).toBe('a');
    client.update('b');
    expect(spawn).toHaveBeenCalledTimes(1);
    expect(w.sent.length).toBe(1);
  });
  it('drops an answer that comes after the worker failed', () => {
    const w = fakeWorker();
    const client = createCitationClient({ spawn: () => w });
    client.update('a');
    const sent = w.sent[0].id;
    w.onerror();
    w.answer(sent, report('late'));
    expect(client.latest().notes.length).toBe(1);
  });
  it('ends a hung worker: a note for its text, and the next text goes to a new worker', async () => {
    const workers = [];
    const client = createCitationClient({ spawn: () => { const w = fakeWorker(); workers.push(w); return w; } });
    const seen = [];
    client.onReport((r) => seen.push(r));
    await client.setSources(fullSources);
    client.update('hung [@k]');
    const pending = client.shareSource('hung');
    const late = workers[0].sent[workers[0].sent.length - 2].id;
    client.restart();
    expect(workers[0].terminate).toHaveBeenCalled();
    await expect(pending).resolves.toBe(null);
    expect(seen).toHaveLength(1);
    expect(seen[0].citations).toEqual([]);
    expect(seen[0].markdownSource).toBe('hung [@k]');
    expect(seen[0].notes).toEqual([{ from: 0, to: 0, line: 0, message: 'The citations stopped: the report took too long.' }]);

    workers[0].answer(late, report('late'));
    expect(seen).toHaveLength(1);

    client.update('next');
    expect(workers).toHaveLength(2);
    expect(workers[1].sent.map((m) => m.type)).toEqual(['sources', 'analyse']);
    expect(workers[1].sent[0].sources.styleXml).toBe('s');
    workers[1].answer(workers[1].sent[1].id, report('next'));
    expect(seen[1]).toEqual(report('next'));
  });
  it('does not repeat the sources in a new worker that gets new sources', async () => {
    const workers = [];
    const client = createCitationClient({ spawn: () => { const w = fakeWorker(); workers.push(w); return w; } });
    await client.setSources(fullSources);
    client.restart();
    await client.setSources({ ...fullSources, styleXml: 'two' });
    expect(workers[1].sent.filter((m) => m.type === 'sources').map((m) => m.sources.styleXml)).toEqual(['two']);
  });
  it('does nothing on a restart with no worker', () => {
    const spawn = vi.fn(fakeWorker);
    const client = createCitationClient({ spawn });
    client.restart();
    expect(spawn).not.toHaveBeenCalled();
    expect(client.latest()).toBe(null);
  });
  it('is frozen, so assigning onReport throws', () => {
    const client = createCitationClient({ spawn: fakeWorker });
    expect(() => { client.onReport = () => {}; }).toThrow(TypeError);
  });
  it('gives the shared text for its own request, apart from the reports', async () => {
    const w = fakeWorker();
    const client = createCitationClient({ spawn: () => w });
    const seen = [];
    client.onReport((r) => seen.push(r));
    client.update('a');
    const first = client.shareSource('one');
    const second = client.shareSource('two');
    const asked = w.sent.filter((m) => m.type === 'share');
    expect(asked.map((m) => m.text)).toEqual(['one', 'two']);
    w.onmessage({ data: { share: asked[1].share, shared: 'two shared' } });
    w.onmessage({ data: { share: asked[0].share, shared: null } });
    await expect(second).resolves.toBe('two shared');
    await expect(first).resolves.toBe(null);
    expect(seen).toEqual([]);
    w.answer(w.sent[0].id, report('a'));
    expect(seen).toEqual([report('a')]);
  });
  it('gives null for a share when no worker can start or a worker fails', async () => {
    const none = createCitationClient({ spawn: () => { throw new Error('no'); } });
    await expect(none.shareSource('a')).resolves.toBe(null);
    const w = fakeWorker();
    const client = createCitationClient({ spawn: () => w });
    const pending = client.shareSource('a');
    w.onerror();
    await expect(pending).resolves.toBe(null);
  });
});
