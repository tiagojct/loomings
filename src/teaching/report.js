// ========================================
// Loomings — one teaching analysis per snapshot
// The checker, the exercise checks and the section limits from a single
// parse, as plain data, so it can run in a worker (worker.js) and typing
// never waits for it — the native app's companion analysis.
// ========================================

import { parseSource } from './parse.js';
import { lint } from './lint.js';
import { evaluate } from './exercises.js';
import { outline, sections, limitsIn } from './sections.js';

/**
 * @typedef {{
 *   issues: import('./lint.js').LintIssue[],
 *   results: import('./exercises.js').CheckResult[],
 *   notes: import('./directives.js').DirectiveNote[],
 *   sections: import('./sections.js').SectionCount[],
 * }} TeachingReport
 */

/**
 * @param {string} text
 * @param {import('./exercises.js').AttachedChecks|null} attached
 * @returns {TeachingReport}
 */
export function analyse(text, attached) {
  const parsed = parseSource(text);
  const issues = lint(text, parsed);
  const report = evaluate(text, attached, parsed);
  const { limits, notes } = limitsIn(text);
  return {
    issues,
    results: report.results,
    notes: [...report.notes, ...notes].sort((a, b) => a.line - b.line),
    sections: limits.length ? sections(text, outline(text, parsed), limits, { onlyLimited: true }) : [],
  };
}
