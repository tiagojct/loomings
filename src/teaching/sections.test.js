import { describe, it, expect } from 'vitest';
import { outline, sections, limitsIn, sectionAt } from './sections.js';

const source = '# T\n\n## A\n\none two\n\n### A1\n\nthree four\n\n## B\n\nfive\n';
const count = (src, limits = []) => sections(src, outline(src), limits);

describe('outline', () => {
  it('lists ATX and setext headings with their line starts, as the native app', () => {
    expect(outline('# One #\n\nTwo\n---\n\n  text\n')).toEqual([
      { level: 1, title: 'One', from: 0 },
      { level: 2, title: 'Two', from: 9 },
    ]);
    expect(outline('---\ntitle: x\n---\n\n## Body\n').map((h) => h.title)).toEqual(['Body']);
  });
});

describe('section word limits', () => {
  it('counts subsections and stops at the next heading of the same level', () => {
    const words = Object.fromEntries(count(source).map((s) => [s.heading.title, s.words]));
    expect(words).toEqual({ T: 8, A: 5, A1: 2, B: 1 });
  });

  it("does not count a section's own heading", () => {
    expect(count('## Long heading with words\n\nbody\n')[0].words).toBe(1);
    expect(count('Long title\n==========\n\nbody\n')[0].words).toBe(1);
  });

  it('matches limits to headings without regard to case or spaces', () => {
    const list = count(source, [{ heading: '  a1 ', maxWords: 3 }, { heading: 'b', maxWords: 10 }]);
    const limit = (title) => list.find((s) => s.heading.title === title)?.limit;
    expect(limit('A1')).toBe(3);
    expect(limit('B')).toBe(10);
    expect(limit('A')).toBeNull();
  });

  it('gives ranges from the heading to where the next one starts', () => {
    const a = count(source).find((s) => s.heading.title === 'A');
    expect(source.slice(a.from, a.to).startsWith('## A')).toBe(true);
    expect(a.to).toBe(source.indexOf('## B'));
  });

  it('counts only limited sections when asked', () => {
    const src = '---\nlimit: A 4\n---\n\n## A\n\none two\n\n## B\n\nthree\n';
    const { limits, notes } = limitsIn(src);
    expect(limits).toEqual([{ heading: 'A', maxWords: 4 }]);
    expect(notes).toEqual([]);
    expect(sections(src, outline(src), limits, { onlyLimited: true }).map((s) => s.heading.title)).toEqual(['A']);
    expect(limitsIn('---\nlimit: A 4\nlimit: nope\n---\n').notes.map((n) => n.line)).toEqual([2]);
  });

  it("finds the caret's innermost limited section, the end included", () => {
    const src = '---\nlimit: A 10\nlimit: A1 3\n---\n\n## A\n\none two\n\n### A1\n\nthree four\n\n## B\n\nfive\n';
    const list = sections(src, outline(src), limitsIn(src).limits, { onlyLimited: true });
    expect(sectionAt(list, src.indexOf('one'))?.heading.title).toBe('A');
    expect(sectionAt(list, src.indexOf('four'))?.heading.title).toBe('A1');
    expect(sectionAt(list, src.indexOf('five'))).toBeNull();
    expect(sectionAt(list, src.indexOf('## B'))?.heading.title).toBe('A1');
  });
});
