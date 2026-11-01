#!/usr/bin/env node
// Generate QR fixtures from the web encoder (src/qr.js). The Swift tests
// render each matrix and decode it with CoreImage, so the web app's QR codes
// are proven readable by a real decoder.
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { qrMatrix } from '../../src/qr.js';
import { shareUrl } from '../../src/share.js';

const here = dirname(fileURLToPath(import.meta.url));
const fixtures = join(here, '..', 'Tests', 'LoomingsShareTests', 'Fixtures');
mkdirSync(fixtures, { recursive: true });

const fill = (seed, bytes) => {
  let text = '';
  while (new TextEncoder().encode(text + seed).length <= bytes) text += seed;
  return text + 'x'.repeat(bytes - new TextEncoder().encode(text).length);
};

const cases = [
  ['word', 'Loomings'],
  ['share link', await shareUrl('# Hello\n\nA short note for the class.\n', 'https://loomings.tiagojacinto.eu/app/')],
  ['portuguese', 'Ciência da informação em saúde, no Porto: ação, coração e pão.'],
  ['emoji', 'Notes 😀 and a whale 🐋 too'],
  ['100 bytes', fill('The quick brown fox jumps over the lazy dog. ', 100)],
  ['300 bytes, with version bits', fill('Call me Ishmael. ', 300)],
  ['1000 bytes, two block lengths', fill('Some years ago, never mind how long precisely. ', 1000)],
  ['2900 bytes, version 40', fill('https://loomings.tiagojacinto.eu/app/#d=z.', 2900)],
];

const out = cases.map(([name, text]) => {
  const matrix = qrMatrix(text);
  if (!matrix) throw new Error(`${name}: too long for a QR code`);
  return { name, text, rows: matrix.map((row) => row.map((dark) => (dark ? '1' : '0')).join('')) };
});
writeFileSync(join(fixtures, 'qr-matrices.json'), JSON.stringify(out, null, 1) + '\n');
console.log(`wrote ${out.length} QR fixtures`);
