#!/usr/bin/env node
// Export the web app's palettes, lessons, example and citation files into
// macos/Resources so the native build shares the same source of truth. Run
// after changing src/palettes.js, lessons/, or examples/. After a change in
// src/citations/, use `npm run export:native`: it builds the bundle first.
import { cpSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { PALETTES, FAMILY_ORDER, DEFAULT_FAMILY, roles } from '../src/palettes.js';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const resources = join(root, 'macos', 'Resources');

const families = {};
for (const name of FAMILY_ORDER) {
  const family = PALETTES[name];
  families[name] = {
    label: family.label,
    modes: family.modes,
    dark: roles(name, 'dark'),
    light: roles(name, 'light'),
  };
}

mkdirSync(resources, { recursive: true });
writeFileSync(
  join(resources, 'palettes.json'),
  JSON.stringify({ defaultFamily: DEFAULT_FAMILY, familyOrder: FAMILY_ORDER, families }, null, 2) + '\n'
);

cpSync(join(root, 'lessons'), join(resources, 'lessons'), { recursive: true });
cpSync(join(root, 'examples', 'loomings.md'), join(resources, 'example.md'));
console.log('exported palettes.json, lessons/ and example.md');

const citations = join(resources, 'Citations');
const bundle = join(root, 'node_modules', '.cache', 'loomings-citations', 'citations.js');
mkdirSync(citations, { recursive: true });
cpSync(join(root, 'src', 'citations', 'styles'), join(citations, 'styles'), { recursive: true });
cpSync(join(root, 'src', 'citations', 'locales'), join(citations, 'locales'), { recursive: true });
cpSync(join(root, 'src', 'citations', 'LICENSE-CSL.md'), join(citations, 'LICENSE-CSL.md'));
cpSync(join(root, 'node_modules', 'citeproc', 'LICENSE'), join(citations, 'LICENSE-citeproc'));
if (existsSync(bundle)) {
  cpSync(bundle, join(citations, 'citations.js'));
  console.log('exported Citations/ with the bundle');
} else {
  console.warn('exported Citations/ without the bundle: run npm run export:native to build it');
}
