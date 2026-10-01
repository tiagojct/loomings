import { describe, it, expect, beforeEach } from 'vitest';
import 'fake-indexeddb/auto';
import {
  idbSet, idbGet, idbDelete, _resetDbForTesting,
  putDocument, getDocument, listDocuments, deleteDocument,
  saveScratch, readScratch, clearScratch,
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
});
