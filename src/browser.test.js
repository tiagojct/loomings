import { describe, it, expect, beforeEach } from 'vitest';
import 'fake-indexeddb/auto';
import {
  idbSet, idbGet, idbDelete, _resetDbForTesting,
  putDocument, getDocument, listDocuments, deleteDocument,
  saveScratch, readScratch, clearScratch,
  openHandle, saveFile, forgetFile,
  listCitationFiles, saveCitationFile, deleteCitationFile, decodeCitationBytes, refreshCitationFiles,
} from './browser.js';

describe('browser storage adapter (IndexedDB)', () => {
  beforeEach(async () => {
    _resetDbForTesting();
    // Clear test keys
    try {
      await idbDelete('test-key');
      await idbDelete('documents');
      await idbDelete('scratch');
    } catch (_) {}
  });

  it('stores, retrieves, and deletes values in kv store', async () => {
    await idbSet('test-key', { foo: 'bar' });
    const val = await idbGet('test-key');
    expect(val).toEqual({ foo: 'bar' });

    await idbDelete('test-key');
    const afterDelete = await idbGet('test-key');
    expect(afterDelete).toBeNull();
  });

  it('normalizes document storage: listDocuments returns metadata without full text', async () => {
    const doc1 = await putDocument({
      id: null,
      title: 'Chapter 1',
      content: 'Call me Ishmael. A long novel begins here...',
    });
    const doc2 = await putDocument({
      id: null,
      title: 'Chapter 2',
      content: 'The carpet-bag. More content...',
    });

    const list = await listDocuments();
    expect(list.length).toBe(2);
    expect(list[0].title).toBe('Chapter 2');
    expect(list[0].id).toBe(doc2.id);
    expect(list[0].content).toBeUndefined(); // content is stripped from index

    // getDocument retrieves content on demand
    const retrieved1 = await getDocument(doc1.id);
    expect(retrieved1.title).toBe('Chapter 1');
    expect(retrieved1.content).toBe('Call me Ishmael. A long novel begins here...');

    const retrieved2 = await getDocument(doc2.id);
    expect(retrieved2.title).toBe('Chapter 2');
    expect(retrieved2.content).toBe('The carpet-bag. More content...');
  });

  it('migrates legacy documents with inline content seamlessly', async () => {
    // Simulate legacy storage format where content was stored inside documents array
    const legacyDoc = {
      id: 'legacy-1',
      title: 'Legacy Title',
      content: 'Legacy Content stored in documents array',
      created: 1000,
      updated: 2000,
    };
    await idbSet('documents', [legacyDoc]);

    const list = await listDocuments();
    expect(list.length).toBe(1);
    expect(list[0].id).toBe('legacy-1');
    expect(list[0].content).toBeUndefined();

    // getDocument should detect legacy content and migrate it
    const doc = await getDocument('legacy-1');
    expect(doc).not.toBeNull();
    expect(doc.content).toBe('Legacy Content stored in documents array');

    // Subsequent retrieval should work from normalized key
    const normalizedContent = await idbGet('doc_content:legacy-1');
    expect(normalizedContent).toBe('Legacy Content stored in documents array');
  });

  it('deletes documents and removes associated content keys', async () => {
    const doc = await putDocument({ id: null, title: 'To Delete', content: 'Soon gone' });
    expect(await getDocument(doc.id)).not.toBeNull();

    await deleteDocument(doc.id);
    expect(await getDocument(doc.id)).toBeNull();
    expect(await idbGet('doc_content:' + doc.id)).toBeNull();
    const list = await listDocuments();
    expect(list.find((d) => d.id === doc.id)).toBeUndefined();
  });

  it('handles scratch buffer operations cleanly', async () => {
    await clearScratch();
    expect(await readScratch()).toBeNull();

    await saveScratch('Draft text', 'notes.md');
    const scratch = await readScratch();
    expect(scratch).toEqual({ content: 'Draft text', current_file: 'notes.md' });

    await clearScratch();
    expect(await readScratch()).toBeNull();
  });

  it('does not adopt a handle whose file could not be read', async () => {
    // A file can vanish between the picker and the read. If the handle is
    // adopted first, the next Save writes the previous document's text into
    // whatever file the handle now points at.
    let writes = 0;
    const halfOpen = {
      kind: 'file',
      name: 'notes.md',
      getFile: async () => ({ name: 'notes.md', text: async () => { throw new Error('unreadable'); } }),
      queryPermission: async () => 'granted',
      createWritable: async () => { writes++; return { write() {}, close() {} }; },
    };

    forgetFile();
    await expect(openHandle(halfOpen)).rejects.toThrow('unreadable');

    // No handle adopted, so there is nothing to write in place: saveFile falls
    // through to a download, which this node environment cannot do.
    await expect(saveFile('notes.md', 'text')).rejects.toThrow();
    expect(writes).toBe(0);
  });
});

describe('citation files', () => {
  beforeEach(async () => {
    _resetDbForTesting();
    for (const f of await listCitationFiles()) await deleteCitationFile(f.name);
  });

  it('saves, lists and deletes', async () => {
    await saveCitationFile({ name: 'refs.bib', kind: 'bib', text: '@a{}' });
    await saveCitationFile({ name: 'x.csl', kind: 'csl', text: '<style/>' });
    const list = await listCitationFiles();
    expect(list.map((f) => f.name).sort()).toEqual(['refs.bib', 'x.csl']);
    expect(list.find((f) => f.name === 'refs.bib').text).toBe('@a{}');
    await deleteCitationFile('refs.bib');
    expect((await listCitationFiles()).map((f) => f.name)).toEqual(['x.csl']);
  });

  it('replaces a file with the same name', async () => {
    await saveCitationFile({ name: 'refs.bib', kind: 'bib', text: 'one' });
    await saveCitationFile({ name: 'refs.bib', kind: 'bib', text: 'two' });
    const list = await listCitationFiles();
    expect(list).toHaveLength(1);
    expect(list[0].text).toBe('two');
  });

  it('contains a failed write', async () => {
    const orig = indexedDB.open;
    indexedDB.open = () => { throw new Error('blocked'); };
    _resetDbForTesting();
    try {
      expect(await saveCitationFile({ name: 'a.bib', kind: 'bib', text: 'x' })).toBe(false);
      expect(await listCitationFiles()).toEqual([]);
      await expect(deleteCitationFile('a.bib')).resolves.toBe(false);
    } finally {
      indexedDB.open = orig;
      _resetDbForTesting();
    }
  });

  it('decodes utf-8, strips a BOM and falls back to windows-1252', () => {
    expect(decodeCitationBytes(new Uint8Array([0xef, 0xbb, 0xbf, 0x61]))).toEqual({ text: 'a', encodingNote: false });
    expect(decodeCitationBytes(new TextEncoder().encode('ção'))).toEqual({ text: 'ção', encodingNote: false });
    expect(decodeCitationBytes(new Uint8Array([0x61, 0xe7]))).toEqual({ text: 'aç', encodingNote: true });
  });

  it('refreshes a stored handle when permission is granted and the text changed', async () => {
    const mk = (perm, text) => ({
      kind: 'file', name: 'r.bib',
      queryPermission: async () => perm,
      getFile: async () => ({ arrayBuffer: async () => new TextEncoder().encode(text).buffer }),
    });
    // Real handles clone into IndexedDB. A fake with functions does not, so keep it by reference.
    const realClone = globalThis.structuredClone;
    globalThis.structuredClone = (v) => (v && typeof v === 'object' && 'handle' in v ? { ...realClone({ ...v, handle: undefined }), handle: v.handle } : realClone(v));
    try {
    await saveCitationFile({ name: 'r.bib', kind: 'bib', text: 'old', handle: mk('granted', 'new') });
    await saveCitationFile({ name: 's.bib', kind: 'bib', text: 'same', handle: mk('granted', 'same') });
    await saveCitationFile({ name: 'p.bib', kind: 'bib', text: 'old', handle: mk('prompt', 'new') });
    const changed = await refreshCitationFiles();
    expect(changed).toEqual(['r.bib']);
    expect((await listCitationFiles()).find((f) => f.name === 'r.bib').text).toBe('new');
    expect((await listCitationFiles()).find((f) => f.name === 'p.bib').text).toBe('old');
    } finally { globalThis.structuredClone = realClone; }
  });
});
