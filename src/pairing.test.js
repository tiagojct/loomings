import { describe, it, expect } from 'vitest';
import { blockForLine, previewBlocks } from './pairing.js';
import { renderPreview } from './markdown.js';

function blocksOf(source) {
  return previewBlocks(renderPreview(source));
}

describe('paired lines', () => {
  const source = '# Title\n\nA paragraph\nover two lines.\n\n| a | b |\n| --- | --- |\n| 1 | 2 |\n| 3 | 4 |\n\n- one\n- two\n\n\nEnd.\n';

  it('reads one block per top-level element, with its source lines', () => {
    expect(blocksOf(source)).toEqual([
      { line: 0, end: 1 },
      { line: 2, end: 4 },
      { line: 5, end: 9 },
      { line: 10, end: 12 },
      { line: 14, end: 15 },
    ]);
  });

  it('finds the whole table from a middle row', () => {
    const blocks = blocksOf(source);
    expect(blockForLine(blocks, 7)).toBe(2);
    expect(blockForLine(blocks, 3)).toBe(1);
    expect(blockForLine(blocks, 11)).toBe(3);
  });

  it('gives -1 for a blank line between blocks, and past the end', () => {
    const blocks = blocksOf(source);
    expect(blockForLine(blocks, 1)).toBe(-1);
    expect(blockForLine(blocks, 4)).toBe(-1);
    expect(blockForLine(blocks, 12)).toBe(-1);
    expect(blockForLine(blocks, 13)).toBe(-1);
    expect(blockForLine(blocks, 99)).toBe(-1);
    expect(blockForLine([], 0)).toBe(-1);
  });

  it('keeps line numbers after frontmatter', () => {
    const blocks = blocksOf('---\ntitle: x\n---\n\n# Body\n');
    expect(blocks).toEqual([{ line: 4, end: 5 }]);
  });
});
