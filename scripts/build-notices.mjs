#!/usr/bin/env node
import { existsSync, mkdirSync, readdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const DEFAULT_ROOT = fileURLToPath(new URL('..', import.meta.url));
const LICENSE_FILE_PATTERN = /^(license|licence|copying|notice)(\.|-|$)/i;

/**
 * @typedef {{
 *   name: string,
 *   version: string,
 *   license: string,
 *   text: string,
 * }} Notice
 */

function readTextIfPresent(filePath) {
  if (!existsSync(filePath)) return null;
  const text = readFileSync(filePath, 'utf8').trim();
  return text.length > 0 ? text : null;
}

function findPackageLicenseText(root, packageDir, packageName) {
  let licenseText = null;
  if (existsSync(packageDir)) {
    const files = readdirSync(packageDir)
      .filter((entry) => LICENSE_FILE_PATTERN.test(entry))
      .sort((a, b) => a.localeCompare(b));
    for (const file of files) {
      const candidate = readTextIfPresent(join(packageDir, file));
      if (candidate) {
        licenseText = candidate;
        break;
      }
    }
  }

  if (!licenseText && packageName.startsWith('@citation-js/')) {
    licenseText = readTextIfPresent(join(root, 'public', 'licenses', 'citation-js-LICENSE.txt'));
  }

  if (packageName === 'citeproc') {
    const cpalText = readTextIfPresent(join(root, 'public', 'licenses', 'CPAL-1.0.txt'));
    if (!cpalText) {
      throw new Error('Missing full CPAL-1.0 license text at public/licenses/CPAL-1.0.txt.');
    }
    return licenseText ? `${licenseText}\n\n${cpalText}` : cpalText;
  }

  return licenseText;
}

function packageNameFromKey(packageKey, pkgJson) {
  if (typeof pkgJson?.name === 'string' && pkgJson.name.trim().length > 0) {
    return pkgJson.name.trim();
  }
  const parts = packageKey.split('node_modules/');
  return parts[parts.length - 1];
}

function collectSupplementalNotices(root) {
  /** @type {Notice[]} */
  const extra = [];

  const rootPkgPath = join(root, 'package.json');
  const rootLicenseText = readTextIfPresent(join(root, 'LICENSE'));
  if (!existsSync(rootPkgPath) || !rootLicenseText) {
    throw new Error('Missing project package.json or LICENSE.');
  }
  const rootPkg = JSON.parse(readFileSync(rootPkgPath, 'utf8'));
  extra.push({
    name: rootPkg.name || 'loomings',
    version: rootPkg.version || '0.0.0',
    license: rootPkg.license || 'MIT',
    text: rootLicenseText,
  });

  const vendorPkgPath = join(root, 'vendor', 'tryworks-design', 'package.json');
  const vendorLicenseText =
    readTextIfPresent(join(root, 'public', 'licenses', 'tryworks-design-LICENSE.txt')) ??
    readTextIfPresent(join(root, 'vendor', 'tryworks-design', 'LICENSE'));
  if (!existsSync(vendorPkgPath) || !vendorLicenseText) {
    throw new Error('Missing vendored @tiagojct/tryworks-design metadata or license text.');
  }
  const vendorPkg = JSON.parse(readFileSync(vendorPkgPath, 'utf8'));
  extra.push({
    name: vendorPkg.name || '@tiagojct/tryworks-design',
    version: vendorPkg.version || '0.1.0',
    license: vendorPkg.license || 'MIT',
    text: vendorLicenseText,
  });

  const cpalText = readTextIfPresent(join(root, 'public', 'licenses', 'CPAL-1.0.txt'));
  if (!cpalText) {
    throw new Error('Missing CPAL-1.0 license text at public/licenses/CPAL-1.0.txt.');
  }
  extra.push({
    name: 'Common Public Attribution License (CPAL-1.0)',
    version: '1.0',
    license: 'CPAL-1.0',
    text: cpalText,
  });

  const cslText =
    readTextIfPresent(join(root, 'public', 'licenses', 'CSL-LICENSE.txt')) ??
    readTextIfPresent(join(root, 'src', 'citations', 'LICENSE-CSL.md'));
  if (cslText) {
    extra.push({
      name: 'CSL Styles and Locales',
      version: 'bundled',
      license: 'CC-BY-SA-3.0',
      text: cslText,
    });
  }

  const fontFiles = [
    {
      name: 'Font: Atkinson Hyperlegible',
      path: join(root, 'public', 'fonts', 'OFL-atkinson-hyperlegible.txt'),
    },
    {
      name: 'Font: Atkinson Hyperlegible Mono',
      path: join(root, 'public', 'licenses', 'OFL-atkinson-hyperlegible-mono.txt'),
    },
    {
      name: 'Font: Atkinson Hyperlegible Next',
      path: join(root, 'public', 'licenses', 'OFL-atkinson-hyperlegible-next.txt'),
    },
    {
      name: 'Font: Barlow Condensed',
      path: join(root, 'public', 'fonts', 'OFL-barlow-condensed.txt'),
    },
    {
      name: 'Font: Caveat',
      path: join(root, 'public', 'fonts', 'OFL-caveat.txt'),
    },
    {
      name: 'Font: JetBrains Mono',
      path: join(root, 'public', 'fonts', 'OFL-jetbrains-mono.txt'),
    },
    {
      name: 'Font: Literata',
      path: join(root, 'public', 'licenses', 'OFL-literata.txt'),
    },
    {
      name: 'Font: Source Serif 4',
      path: join(root, 'public', 'fonts', 'OFL-source-serif-4.txt'),
    },
  ];

  for (const font of fontFiles) {
    const text = readTextIfPresent(font.path);
    if (!text) {
      throw new Error(`Missing font license text for ${font.name} at ${font.path}.`);
    }
    extra.push({
      name: font.name,
      version: '1.1',
      license: 'OFL-1.1',
      text,
    });
  }

  return extra;
}

/**
 * @param {string} [root]
 * @returns {Notice[]}
 */
export function collectNotices(root = DEFAULT_ROOT) {
  const lockfilePath = join(root, 'package-lock.json');
  if (!existsSync(lockfilePath)) {
    throw new Error(`Missing package-lock.json in ${root}.`);
  }
  const lockfile = JSON.parse(readFileSync(lockfilePath, 'utf8'));
  const packages = lockfile.packages ?? {};

  /** @type {Notice[]} */
  const packageNotices = [];
  const seen = new Set();

  for (const [packageKey, meta] of Object.entries(packages)) {
    if (packageKey === '' || meta?.dev === true) continue;

    const packageDir = join(root, packageKey);
    const pkgJsonPath = join(packageDir, 'package.json');
    const pkgJson = existsSync(pkgJsonPath)
      ? JSON.parse(readFileSync(pkgJsonPath, 'utf8'))
      : {};

    const name = packageNameFromKey(packageKey, pkgJson);
    const version = String(meta?.version ?? pkgJson?.version ?? '').trim();
    const license = String(meta?.license ?? pkgJson?.license ?? '').trim();
    const text = findPackageLicenseText(root, packageDir, name);

    if (!version || !license || !text) {
      throw new Error(
        `Production package "${name}" (${packageKey}) is missing required license metadata or license text.`,
      );
    }

    const dedupeKey = `${name}@${version}`;
    if (seen.has(dedupeKey)) continue;
    seen.add(dedupeKey);

    packageNotices.push({ name, version, license, text });
  }

  packageNotices.sort((a, b) => a.name.localeCompare(b.name) || a.version.localeCompare(b.version));

  const supplemental = collectSupplementalNotices(root);
  return [...packageNotices, ...supplemental];
}

/**
 * @param {Notice[]} notices
 * @returns {string}
 */
export function renderNotices(notices) {
  const blocks = notices.map((notice) => [
    '================================================================================',
    `${notice.name} (${notice.version})`,
    `License: ${notice.license}`,
    '================================================================================',
    '',
    notice.text.trim(),
  ].join('\n'));

  return [
    'THIRD-PARTY SOFTWARE AND ASSET NOTICES',
    '',
    ...blocks,
    '',
  ].join('\n\n');
}

/**
 * @param {'web' | 'native'} target
 * @param {string} [root]
 * @returns {string}
 */
export function writeNotices(target, root = DEFAULT_ROOT) {
  if (target !== 'web' && target !== 'native') {
    throw new Error(`Invalid target "${target}". Expected "web" or "native".`);
  }

  const outputPath =
    target === 'web'
      ? join(root, 'public', 'licenses', 'THIRD-PARTY-NOTICES.txt')
      : join(root, 'macos', 'Resources', 'THIRD-PARTY-NOTICES.txt');

  const content = renderNotices(collectNotices(root));
  mkdirSync(dirname(outputPath), { recursive: true });
  const tempPath = `${outputPath}.tmp-${process.pid}`;
  writeFileSync(tempPath, content, 'utf8');
  renameSync(tempPath, outputPath);
  return outputPath;
}

function runCli() {
  try {
    const arg = process.argv[2] ?? 'web';
    if (arg === 'all') {
      writeNotices('web');
      writeNotices('native');
      return;
    }
    if (arg !== 'web' && arg !== 'native') {
      throw new Error(`Usage: node scripts/build-notices.mjs <web|native|all>`);
    }
    writeNotices(arg);
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  }
}

if (
  process.argv[1] &&
  pathToFileURL(resolve(process.argv[1])).href === import.meta.url
) {
  runCli();
}
