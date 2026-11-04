// Find ignores accents, so "ciencia" finds "ciência" and "saúde" finds "saude".
// @codemirror/search takes no normalizer, so this wraps the one each cursor
// sets on itself; search.test.js fails if the library stops setting it. A
// Match case search keeps its exact comparison, accents included.

import { SearchCursor } from '@codemirror/search';

const withoutAccents = (text) => text.normalize('NFD').replace(/\p{Mn}/gu, '');
const normalizers = new WeakMap();

Object.defineProperty(SearchCursor.prototype, 'normalize', {
  configurable: true,
  get() { return normalizers.get(this); },
  /** @param {(text: string) => string} normalize */
  set(normalize) {
    const foldsCase = normalize('A') !== 'A';
    normalizers.set(this, foldsCase ? (text) => withoutAccents(normalize(text)) : normalize);
  },
});
