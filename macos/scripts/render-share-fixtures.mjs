#!/usr/bin/env node
// Generate cross-language share fixtures from the web implementation. The
// Swift tests decode these payloads and URLs; the reverse direction runs the
// web decoder from the Swift test suite.
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { encodeDoc } from '../../src/share.js';

const here = dirname(fileURLToPath(import.meta.url));
const fixtures = join(here, '..', 'Tests', 'LoomingsShareTests', 'Fixtures');
mkdirSync(fixtures, { recursive: true });

const cases = [
  ['empty', ''],
  ['ascii', '# Hello\n\nA plain document.\n'],
  ['unicode', '# Título\n\nÀ noite, *ninguém* escreve — ou escreve? 🐋\n'],
  ['repetitive', 'Call me Ishmael. '.repeat(400)],
  ['markdown', '# One\n\n- a\n- b\n\n```js\nconsole.log("olá");\n```\n'],
];

const out = [];
for (const [name, text] of cases) {
  const payload = await encodeDoc(text);
  const url = `https://loomings.tiagojacinto.eu/app/?theme=goney&mode=dark#d=${payload}`;
  out.push({ name, text, payload, url, family: 'goney', mode: 'dark' });
}

writeFileSync(join(fixtures, 'share-fixtures.json'), JSON.stringify(out, null, 2) + '\n');
console.log(`wrote ${out.length} share fixtures`);
