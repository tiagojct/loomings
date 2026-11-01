// ========================================
// Loomings — line and word differences
// A port of the native LineDiff (macos/Sources/LoomingsTeaching/LineDiff.swift):
// Myers' O(ND) comparison after the common start and end are taken off,
// searched up to an edit distance of 2,000 (past that, all removed then all
// added). `addedText` keeps only what a new text adds to an old one.
// ========================================

const CAP = 2000;

/**
 * @typedef {{op: 'same', old: number, new: number} | {op: 'removed', old: number} | {op: 'added', new: number}} DiffOp
 */

/**
 * @template T
 * @param {T[]} a
 * @param {T[]} b
 * @returns {DiffOp[]}
 */
export function diff(a, b) {
  let prefix = 0;
  while (prefix < a.length && prefix < b.length && a[prefix] === b[prefix]) prefix++;
  let suffix = 0;
  while (suffix < a.length - prefix && suffix < b.length - prefix && a[a.length - 1 - suffix] === b[b.length - 1 - suffix]) suffix++;
  /** @type {DiffOp[]} */
  const ops = [];
  for (let i = 0; i < prefix; i++) ops.push({ op: 'same', old: i, new: i });
  const middleA = a.slice(prefix, a.length - suffix);
  const middleB = b.slice(prefix, b.length - suffix);
  const middle = myers(middleA, middleB);
  if (middle) {
    for (const op of middle) {
      if (op.op === 'same') ops.push({ op: 'same', old: op.old + prefix, new: op.new + prefix });
      else if (op.op === 'removed') ops.push({ op: 'removed', old: op.old + prefix });
      else ops.push({ op: 'added', new: op.new + prefix });
    }
  } else {
    middleA.forEach((_, i) => ops.push({ op: 'removed', old: i + prefix }));
    middleB.forEach((_, i) => ops.push({ op: 'added', new: i + prefix }));
  }
  for (let i = 0; i < suffix; i++) ops.push({ op: 'same', old: a.length - suffix + i, new: b.length - suffix + i });
  return ops;
}

/**
 * The shortest edit script, or null when it is longer than CAP.
 *
 * @template T
 * @param {T[]} a
 * @param {T[]} b
 * @returns {DiffOp[]|null}
 */
function myers(a, b) {
  const n = a.length;
  const m = b.length;
  if (n === 0) return b.map((_, i) => ({ op: /** @type {const} */ ('added'), new: i }));
  if (m === 0) return a.map((_, i) => ({ op: /** @type {const} */ ('removed'), old: i }));
  const limit = Math.min(n + m, CAP);
  const offset = limit + 1;
  const v = new Array(2 * limit + 3).fill(0);
  /** @type {number[][]} */
  const trace = [];
  for (let d = 0; d <= limit; d++) {
    for (let k = -d; k <= d; k += 2) {
      let x = (k === -d || (k !== d && v[offset + k - 1] < v[offset + k + 1])) ? v[offset + k + 1] : v[offset + k - 1] + 1;
      let y = x - k;
      while (x < n && y < m && a[x] === b[y]) { x++; y++; }
      v[offset + k] = x;
      if (x >= n && y >= m) return backtrack(trace, d, n, m);
    }
    trace.push(v.slice(offset - d, offset + d + 1));
  }
  return null;
}

/** Walks back through the saved frontiers; trace[d] holds x for diagonals -d..d. */
function backtrack(trace, final, n, m) {
  /** @type {DiffOp[]} */
  const ops = [];
  let x = n;
  let y = m;
  for (let d = final; d > 0; d--) {
    const previous = trace[d - 1];
    const frontier = (k) => previous[k + d - 1];
    const k = x - y;
    const previousK = (k === -d || (k !== d && frontier(k - 1) < frontier(k + 1))) ? k + 1 : k - 1;
    const previousX = frontier(previousK);
    const previousY = previousX - previousK;
    while (x > previousX && y > previousY) { ops.push({ op: 'same', old: x - 1, new: y - 1 }); x--; y--; }
    if (x === previousX) { ops.push({ op: 'added', new: y - 1 }); y--; }
    else { ops.push({ op: 'removed', old: x - 1 }); x--; }
  }
  while (x > 0 && y > 0) { ops.push({ op: 'same', old: x - 1, new: y - 1 }); x--; y--; }
  return ops.reverse();
}

/** Runs of white space and runs of other characters, in order. */
function tokens(text) {
  return text.match(/\s+|\S+/g) || [];
}

/**
 * The words of `newLine` that `oldLine` does not have, white space not counted.
 *
 * @param {string} oldLine
 * @param {string} newLine
 * @returns {string[]}
 */
export function addedWords(oldLine, newLine) {
  const a = tokens(oldLine);
  const b = tokens(newLine);
  return diff(a, b).flatMap((op) => (op.op === 'added' && /\S/.test(b[op.new]) ? [b[op.new]] : []));
}

/**
 * What `newText` adds to `oldText`: lines it adds whole, and for a line it
 * changes, only the words it adds (one line of them per changed line).
 *
 * @param {string} oldText
 * @param {string} newText
 * @returns {string}
 */
export function addedText(oldText, newText) {
  const a = oldText.split('\n');
  const b = newText.split('\n');
  /** @type {string[]} */
  const out = [];
  /** @type {number[]} */ let removed = [];
  /** @type {number[]} */ let added = [];
  const flush = () => {
    added.forEach((line, i) => {
      if (i < removed.length) {
        const words = addedWords(a[removed[i]], b[line]);
        if (words.length) out.push(words.join(' '));
      } else {
        out.push(b[line]);
      }
    });
    removed = [];
    added = [];
  };
  for (const op of diff(a, b)) {
    if (op.op === 'same') flush();
    else if (op.op === 'removed') removed.push(op.old);
    else added.push(op.new);
  }
  flush();
  return out.join('\n');
}
