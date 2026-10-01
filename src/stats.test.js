import { describe, it, expect } from 'vitest';
import { countWords, readingTime } from './stats.js';

describe('stats calculation', () => {
  it('counts words in empty or whitespace text as 0', () => {
    expect(countWords('')).toBe(0);
    expect(countWords('   ')).toBe(0);
    expect(countWords('\n\t\r ')).toBe(0);
    expect(countWords(null)).toBe(0);
  });

  it('counts standard words accurately', () => {
    expect(countWords('Call me Ishmael.')).toBe(3);
    expect(countWords('One  two   three    four')).toBe(4);
    expect(countWords('# Heading One\n\nParagraph text goes here.')).toBe(7);
  });

  it('handles unicode whitespace correctly', () => {
    // \u3000 is ideographic space, \u2003 is em-space
    const unicodeText = 'Word1\u3000Word2\u2003Word3';
    expect(countWords(unicodeText)).toBe(3);
  });

  it('computes reading time estimates', () => {
    expect(readingTime(0)).toBe('');
    expect(readingTime(50)).toBe('~1 min');
    expect(readingTime(200)).toBe('~1 min');
    expect(readingTime(350)).toBe('~2 min');
    expect(readingTime(1000)).toBe('~5 min');
  });
});
