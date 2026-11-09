import { describe, it, expect } from 'vitest';
import { saveAction } from './save-route.js';

describe('save routing', () => {
  it('writes to a browser document in place', () => {
    expect(saveAction({ file: null, docId: 'doc-1', writable: false, hasFsa: true })).toBe('save-now');
  });

  it('writes to a file that has a handle', () => {
    expect(saveAction({ file: 'notes.md', docId: null, writable: true, hasFsa: true })).toBe('save-now');
  });

  it('keeps a file without a handle as a browser document', () => {
    expect(saveAction({ file: 'notes.md', docId: null, writable: false, hasFsa: false })).toBe('save-in-browser');
  });

  it('picks a file for an untitled buffer where the browser can write one', () => {
    expect(saveAction({ file: null, docId: null, writable: false, hasFsa: true })).toBe('save-as');
  });

  it('stores an untitled buffer in the browser where it cannot write a file', () => {
    expect(saveAction({ file: null, docId: null, writable: false, hasFsa: false })).toBe('save-in-browser');
  });
});
