import { describe, it, expect } from 'vitest';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { lint } from './lint.js';

const root = fileURLToPath(new URL('../../', import.meta.url));
const fixtures = join(root, 'macos/Tests/LoomingsTeachingTests/Fixtures');

/** Applies every fix, last first, so earlier offsets stay valid. */
function applyFixes(issues, source) {
  let text = source;
  const fixes = issues.map((i) => i.fix).filter(Boolean).sort((a, b) => b.from - a.from);
  for (const fix of fixes) text = text.slice(0, fix.from) + fix.insert + text.slice(fix.to);
  return text;
}

describe("learner's checker: shared cases", () => {
  const cases = JSON.parse(readFileSync(join(fixtures, 'lint-cases.json'), 'utf8'));

  it('has the native cases', () => {
    expect(cases.length).toBeGreaterThanOrEqual(25);
  });

  for (const item of cases) {
    it(item.name, () => {
      const issues = lint(item.source);
      expect(issues.map((i) => i.rule)).toEqual(item.rules);
      expect(applyFixes(issues, item.source)).toBe(item.fixed);
      for (const issue of issues) {
        expect(issue.message).not.toBe('');
        expect(issue.from).toBeGreaterThanOrEqual(0);
        expect(issue.to).toBeLessThanOrEqual(item.source.length);
        expect(issue.from).toBeLessThanOrEqual(issue.to);
      }
    });
  }
});

describe("learner's checker", () => {
  it('fix offsets are UTF-16 and survive emoji and CRLF', () => {
    const source = '😀 x\r\n#Title\r\n';
    const issues = lint(source);
    expect(issues.map((i) => i.rule)).toEqual(['heading-space']);
    expect(applyFixes(issues, source)).toBe('😀 x\r\n# Title\r\n');
  });

  it('keeps a CRLF document CRLF when it adds lines', () => {
    expect(applyFixes(lint('| a | b |\r\n| 1 | 2 |\r\n'), '| a | b |\r\n| 1 | 2 |\r\n'))
      .toBe('| a | b |\r\n| --- | --- |\r\n| 1 | 2 |\r\n');
    expect(applyFixes(lint('```\r\ncode\r\n'), '```\r\ncode\r\n')).toBe('```\r\ncode\r\n```\r\n');
  });

  it('never checks code blocks or inline code', () => {
    expect(lint('```\n#Title\n[a](b c)\n```\n')).toEqual([]);
    expect(lint('Use `[a](b c)` as an example.\n')).toEqual([]);
    expect(lint('    #Title\n')).toEqual([]);
  });

  it('gives notes sorted by position', () => {
    const issues = lint('![](a.png)\n\n#One\n\n#Two\n');
    expect(issues.length).toBe(3);
    expect(issues.map((i) => i.from)).toEqual([...issues.map((i) => i.from)].sort((a, b) => a - b));
  });

  it('marks the leftover marks themselves, and the whole image', () => {
    const source = '**a** and **b\n\nSee ![](x.png) here.\n';
    const [marks, image] = lint(source);
    expect(source.slice(marks.from, marks.to)).toBe('**');
    expect(marks.from).toBe(10);
    expect(source.slice(image.from, image.to)).toBe('![](x.png)');
  });

  it('finds marks and images inside lists, quotations, headings and tables', () => {
    expect(lint('- an **item\n').map((i) => i.rule)).toEqual(['unpaired-emphasis']);
    expect(lint('> a **quote\n').map((i) => i.rule)).toEqual(['unpaired-emphasis']);
    expect(lint('## A **title\n').map((i) => i.rule)).toEqual(['unpaired-emphasis']);
    const table = '| a | b |\n| --- | --- |\n| x | ![](y.png) |\n';
    const [cell] = lint(table);
    expect(cell.rule).toBe('image-alt');
    expect(table.slice(cell.from, cell.to)).toBe('![](y.png)');
  });

  it('checks paragraph lines only where the paragraph starts a line', () => {
    expect(lint('- item\n  #Title\n')).toEqual([]);
    expect(lint('> see [a](b c)\n')).toEqual([]);
    expect(lint('   #Title\n').map((i) => i.rule)).toEqual(['heading-space']);
  });

  it('is quiet on an empty or blank document', () => {
    expect(lint('')).toEqual([]);
    expect(lint('\n\n  \n')).toEqual([]);
  });
});

describe('checker on bundled material', () => {
  it('lessons, the example and the cheatsheet raise no notes', () => {
    const lessons = readdirSync(join(root, 'lessons')).filter((f) => f.endsWith('.md'));
    expect(lessons.length).toBe(6);
    const files = [
      ...lessons.map((f) => join(root, 'lessons', f)),
      join(root, 'examples/loomings.md'),
      join(root, 'macos/Resources/cheatsheet.md'),
    ];
    for (const file of files) {
      const issues = lint(readFileSync(file, 'utf8'));
      expect(issues.map((i) => `${i.rule}@${i.from}`), file).toEqual([]);
    }
  });
});
