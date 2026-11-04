import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { sanitiseItem } from './item.js';
import { createEngine } from './engine.js';

const style = (n) => readFileSync(new URL(`./styles/${n}.csl`, import.meta.url), 'utf8');
const locale = readFileSync(new URL('./locales/locales-en-US.xml', import.meta.url), 'utf8');

describe('sanitiseItem', () => {
  it('keeps a good item as it is', () => {
    const item = {
      id: 'a', type: 'book', title: 'T', volume: '3', author: [{ family: 'S', given: 'J' }, { literal: 'WHO' }],
      issued: { 'date-parts': [[2020, 1, 2]] }, accessed: { raw: '2020-01-02' }, 'event-date': { literal: 'Spring' },
    };
    expect(sanitiseItem(item)).toEqual(item);
  });
  it('turns numbers into text', () => {
    expect(sanitiseItem({ id: 'a', title: 5, DOI: 6, volume: 7 })).toEqual({ id: 'a', title: '5', DOI: '6', volume: '7' });
  });
  it('drops values of a wrong type', () => {
    expect(sanitiseItem({ id: 'a', title: {}, volume: [], note: null, type: true })).toEqual({ id: 'a' });
  });
  it('repairs a name list', () => {
    expect(sanitiseItem({ id: 'a', author: [null, 1, 'x', [], {}, { family: 5, given: {} }, { family: 'S' }] }))
      .toEqual({ id: 'a', author: [{ family: '5' }, { family: 'S' }] });
    expect(sanitiseItem({ id: 'a', editor: 'Smith' })).toEqual({ id: 'a' });
    expect(sanitiseItem({ id: 'a', translator: [null] })).toEqual({ id: 'a' });
  });
  it('repairs a date', () => {
    expect(sanitiseItem({ id: 'a', issued: { raw: 5 } })).toEqual({ id: 'a', issued: { raw: '5' } });
    expect(sanitiseItem({ id: 'a', issued: { 'date-parts': [['2020', 1]] } })).toEqual({ id: 'a', issued: { 'date-parts': [['2020', 1]] } });
    for (const issued of [null, 5, 'x', [], {}, { 'date-parts': 'x' }, { 'date-parts': [] }, { 'date-parts': [[]] }, { 'date-parts': [[null]] }, { 'date-parts': [['a', {}]] }, { season: {} }]) {
      expect(sanitiseItem({ id: 'a', issued })).toEqual({ id: 'a' });
    }
  });
  it('makes no prototype changes', () => {
    const item = sanitiseItem(JSON.parse('{"id":"a","__proto__":{"x":1}}'));
    expect(item.x).toBeUndefined();
    expect(Object.getPrototypeOf(item)).toBe(Object.prototype);
  });
});

describe('sanitised items and citeproc', () => {
  const values = [null, 5, true, 's', [], [null], [1], ['x'], {}, { a: 1 }, [{ a: 1 }], [{ family: null }], [{ family: 5, given: {} }],
    [[]], [['x']], { 'date-parts': [[null]] }, { 'date-parts': [['a', {}]] }, { 'date-parts': [] }, { 'date-parts': [[]] },
    { raw: 5 }, { literal: {} }, { season: {} }, { 'date-parts': [[2020]], circa: {} }];
  const fields = ['title', 'author', 'editor', 'translator', 'issued', 'accessed', 'DOI', 'URL', 'ISBN', 'page', 'volume', 'issue', 'type',
    'language', 'note', 'container-title', 'publisher', 'number', 'edition', 'original-date', 'custom', 'title-short', 'citation-number',
    'locator', 'year-suffix', 'multi', 'seeAlso', 'jurisdiction', 'categories', 'event-date', 'status', 'genre', 'references'];
  const items = fields.flatMap((field) => values.map((value, n) => sanitiseItem({
    id: `${field}-${n}`, type: 'article-journal', title: 'T', author: [{ family: 'S' }], issued: { 'date-parts': [[2020]] }, [field]: value,
  })));
  const cite = (key, bare) => ({
    from: 0, to: 1, bare, items: [{ key, prefix: '', suffix: '', locator: null, label: null, suppressAuthor: false }],
  });
  it.each(['apa', 'vancouver'])('gives no throw in %s for any bad field', (name) => {
    const engine = createEngine({ styleXml: style(name), localeXml: locale, lang: 'en-US', items });
    const failed = [];
    for (const item of items) {
      for (const bare of [false, true]) {
        try {
          engine.render([cite(item.id, bare)]);
        } catch (e) {
          failed.push(`${item.id}: ${e.message}`);
        }
      }
    }
    expect(failed).toEqual([]);
  }, 30000);
});
