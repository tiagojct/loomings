import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { analyse } from './report.js';
import { lint } from './lint.js';
import { evaluate } from './exercises.js';
import { outline, sections, limitsIn } from './sections.js';
import { parseSource } from './parse.js';

const lesson = readFileSync(new URL('../../lessons/02-lists-quotes.md', import.meta.url), 'utf8');
const doc = '---\nlimit: Intro 3\ncheck: heading 2\ncheck: banana\n---\n\n## Intro\n\none two three four\n\n#Oops\n';

describe('one analysis per snapshot', () => {
  it('gives the same notes, checks and sections as the separate calls', () => {
    for (const [text, attached] of [[doc, null], [lesson + '\n- a\n- b\n', { checks: [{ type: 'bulletList', items: 2 }], after: lesson }]]) {
      const report = analyse(text, attached);
      expect(report.issues).toEqual(lint(text));
      const checks = evaluate(text, attached);
      const { limits, notes } = limitsIn(text);
      expect(report.results).toEqual(checks.results);
      expect(report.notes).toEqual([...checks.notes, ...notes].sort((a, b) => a.line - b.line));
      expect(report.sections).toEqual(limits.length ? sections(text, outline(text), limits, { onlyLimited: true }) : []);
    }
  });

  it('lets the rules share one parse', () => {
    const parsed = parseSource(doc);
    expect(lint(doc, parsed)).toEqual(lint(doc));
    expect(outline(doc, parsed)).toEqual(outline(doc));
    expect(evaluate(doc, null, parsed)).toEqual(evaluate(doc));
  });

  it('returns plain data a worker can post', () => {
    const report = analyse(doc, null);
    expect(JSON.parse(JSON.stringify(report))).toEqual(report);
  });
});
