#!/usr/bin/env node
// Export the web app's palettes, lessons, example and citation files into
// macos/Resources so the native build shares the same source of truth. Run
// after changing src/palettes.js, lessons/, or examples/. After a change in
// src/citations/, use `npm run export:native`: it builds the bundle first.
import { randomUUID } from 'node:crypto';
import { cpSync, existsSync, mkdirSync, mkdtempSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import { basename, dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { PALETTES, FAMILY_ORDER, DEFAULT_FAMILY, roles } from '../src/palettes.js';
import { BUNDLED_LOCALES, BUNDLED_STYLES, LOCALE_LABELS } from '../src/citations/style.js';
import { writeNotices } from './build-notices.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const resources = join(root, 'macos', 'Resources');

/**
 * Replace a destination directory with a complete copy of a source directory.
 *
 * @param {string} source
 * @param {string} destination
 */
export function mirrorDirectory(source, destination) {
  const parent = dirname(destination);
  const name = basename(destination);
  mkdirSync(parent, { recursive: true });
  const staging = mkdtempSync(join(parent, `.${name}.tmp-`));
  const backup = join(parent, `.${name}.backup-${randomUUID()}`);
  let destinationBackedUp = false;
  let destinationInstalled = false;

  try {
    cpSync(source, staging, { recursive: true });

    if (existsSync(destination)) {
      renameSync(destination, backup);
      destinationBackedUp = true;
    }

    renameSync(staging, destination);
    destinationInstalled = true;

    if (destinationBackedUp) {
      rmSync(backup, { recursive: true });
      destinationBackedUp = false;
    }
  } catch (error) {
    if (destinationInstalled) {
      rmSync(destination, { recursive: true, force: true });
      destinationInstalled = false;
    }
    if (destinationBackedUp) {
      renameSync(backup, destination);
      destinationBackedUp = false;
    }
    throw error;
  } finally {
    rmSync(staging, { recursive: true, force: true });
    if (destinationBackedUp && !existsSync(destination)) {
      renameSync(backup, destination);
    }
  }
}

function exportNativeResources() {
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

  mirrorDirectory(join(root, 'lessons'), join(resources, 'lessons'));
  cpSync(join(root, 'examples', 'loomings.md'), join(resources, 'example.md'));
  console.log('exported palettes.json, lessons/ and example.md');

  const citations = join(resources, 'Citations');
  const bundle = join(root, 'node_modules', '.cache', 'loomings-citations', 'citations.js');
  mkdirSync(citations, { recursive: true });
  writeNotices('native', root);
  mirrorDirectory(join(root, 'src', 'citations', 'styles'), join(citations, 'styles'));
  mirrorDirectory(join(root, 'src', 'citations', 'locales'), join(citations, 'locales'));
  cpSync(join(root, 'src', 'citations', 'LICENSE-CSL.md'), join(citations, 'LICENSE-CSL.md'));
  cpSync(join(root, 'node_modules', 'citeproc', 'LICENSE'), join(citations, 'LICENSE-citeproc'));
  cpSync(join(root, 'public', 'licenses', 'CPAL-1.0.txt'), join(citations, 'CPAL-1.0.txt'));
  cpSync(join(root, 'public', 'licenses', 'citation-js-LICENSE.txt'), join(citations, 'LICENSE-citation-js'));
  cpSync(join(resources, 'THIRD-PARTY-NOTICES.txt'), join(citations, 'THIRD-PARTY-NOTICES.txt'));
  // The titles for the native menu. The menu needs them before JavaScript runs.
  writeFileSync(
    join(citations, 'styles.json'),
    JSON.stringify({
      styles: BUNDLED_STYLES,
      languages: BUNDLED_LOCALES.map((id) => ({ id, label: LOCALE_LABELS[id] ?? id })),
    }, null, 2) + '\n'
  );
  if (existsSync(bundle)) {
    cpSync(bundle, join(citations, 'citations.js'));
    console.log('exported Citations/ with the bundle');
  } else {
    console.warn('exported Citations/ without the bundle: run npm run export:native to build it');
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  exportNativeResources();
}
