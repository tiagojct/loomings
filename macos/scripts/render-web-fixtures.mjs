#!/usr/bin/env node
// Regenerates the preview HTML fixtures from the web renderer, so Stage 4
// parity tests compare against the same markdown-it configuration the app
// ships. Run after changing src/markdown.js or adding a .md fixture.
import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { renderMarkdown } from '../../src/markdown.js';

const here = dirname(fileURLToPath(import.meta.url));
const fixtures = join(here, '..', 'Tests', 'LoomingsPreviewTests', 'Fixtures');

for (const name of readdirSync(fixtures)) {
  if (!name.endsWith('.md')) continue;
  const source = readFileSync(join(fixtures, name), 'utf8');
  writeFileSync(join(fixtures, name.replace(/\.md$/, '.html')), renderMarkdown(source));
}
console.log(`rendered ${readdirSync(fixtures).filter((f) => f.endsWith('.md')).length} fixtures`);
