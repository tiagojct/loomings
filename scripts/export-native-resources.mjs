#!/usr/bin/env node
// Export the web app's palettes, lessons and example into macos/Resources so
// the native build shares the same source of truth. Run after changing
// src/palettes.js, lessons/, or examples/.
import { cpSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
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
