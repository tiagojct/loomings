import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { collectNotices, renderNotices, writeNotices } from '../scripts/build-notices.mjs';

const REPO_ROOT = fileURLToPath(new URL('..', import.meta.url));

function createFixture({ includeMissingProd = false } = {}) {
  const root = mkdtempSync(join(tmpdir(), 'loomings-notices-'));
  mkdirSync(join(root, 'public', 'licenses'), { recursive: true });
  mkdirSync(join(root, 'public', 'fonts'), { recursive: true });
  mkdirSync(join(root, 'vendor', 'tryworks-design'), { recursive: true });
  mkdirSync(join(root, 'node_modules', 'prod-pkg'), { recursive: true });
  mkdirSync(join(root, 'node_modules', 'dev-pkg'), { recursive: true });

  writeFileSync(
    join(root, 'package.json'),
    JSON.stringify({ name: 'loomings', version: '2.6.5', license: 'MIT' }),
  );
  writeFileSync(join(root, 'LICENSE'), 'MIT License\nCopyright (c) 2026 Tiago Jacinto\n');
  writeFileSync(
    join(root, 'vendor', 'tryworks-design', 'package.json'),
    JSON.stringify({ name: '@tiagojct/tryworks-design', version: '0.1.0', license: 'MIT' }),
  );
  writeFileSync(
    join(root, 'public', 'licenses', 'tryworks-design-LICENSE.txt'),
    'MIT License\nTryworks Design\n',
  );
  writeFileSync(
    join(root, 'public', 'licenses', 'CPAL-1.0.txt'),
    'Common Public Attribution License Version 1.0 (CPAL)\n',
  );
  writeFileSync(
    join(root, 'public', 'licenses', 'CSL-LICENSE.txt'),
    '# CSL styles and locales\nCC BY-SA 3.0\n',
  );
  writeFileSync(
    join(root, 'public', 'licenses', 'OFL-literata.txt'),
    'Copyright 2017 The Literata Project Authors\nSIL OPEN FONT LICENSE Version 1.1\n',
  );
  writeFileSync(
    join(root, 'public', 'licenses', 'OFL-atkinson-hyperlegible-next.txt'),
    'Copyright 2020-2024 The Atkinson Hyperlegible Next Project Authors\nSIL OPEN FONT LICENSE Version 1.1\n',
  );
  writeFileSync(
    join(root, 'public', 'licenses', 'OFL-atkinson-hyperlegible-mono.txt'),
    'Copyright 2020-2024 The Atkinson Hyperlegible Mono Project Authors\nSIL OPEN FONT LICENSE Version 1.1\n',
  );
  writeFileSync(
    join(root, 'public', 'fonts', 'OFL-atkinson-hyperlegible.txt'),
    'Copyright 2020 Braille Institute of America, Inc.\nSIL OPEN FONT LICENSE Version 1.1\n',
  );
  writeFileSync(
    join(root, 'public', 'fonts', 'OFL-barlow-condensed.txt'),
    'Copyright 2017 The Barlow Project Authors\nSIL OPEN FONT LICENSE Version 1.1\n',
  );
  writeFileSync(
    join(root, 'public', 'fonts', 'OFL-caveat.txt'),
    'Copyright 2014 The Caveat Project Authors\nSIL OPEN FONT LICENSE Version 1.1\n',
  );
  writeFileSync(
    join(root, 'public', 'fonts', 'OFL-jetbrains-mono.txt'),
    'Copyright 2020 The JetBrains Mono Project Authors\nSIL OPEN FONT LICENSE Version 1.1\n',
  );
  writeFileSync(
    join(root, 'public', 'fonts', 'OFL-source-serif-4.txt'),
    'Copyright 2014 The Source Serif 4 Project Authors\nSIL OPEN FONT LICENSE Version 1.1\n',
  );

  writeFileSync(
    join(root, 'node_modules', 'prod-pkg', 'package.json'),
    JSON.stringify({ name: 'prod-pkg', version: '1.2.3', license: 'MIT' }),
  );
  writeFileSync(
    join(root, 'node_modules', 'prod-pkg', 'LICENSE'),
    'MIT License\nCopyright (c) Prod Pkg\n',
  );
  writeFileSync(
    join(root, 'node_modules', 'dev-pkg', 'package.json'),
    JSON.stringify({ name: 'dev-pkg', version: '9.9.9', license: 'MIT' }),
  );

  /** @type {Record<string, unknown>} */
  const packages = {
    '': { name: 'loomings', version: '2.6.5', license: 'MIT' },
    'node_modules/prod-pkg': { version: '1.2.3', license: 'MIT' },
    'node_modules/dev-pkg': { version: '9.9.9', license: 'MIT', dev: true },
  };

  if (includeMissingProd) {
    mkdirSync(join(root, 'node_modules', 'missing-license-pkg'), { recursive: true });
    writeFileSync(
      join(root, 'node_modules', 'missing-license-pkg', 'package.json'),
      JSON.stringify({ name: 'missing-license-pkg', version: '0.1.0', license: 'MIT' }),
    );
    packages['node_modules/missing-license-pkg'] = { version: '0.1.0', license: 'MIT' };
  }

  writeFileSync(
    join(root, 'package-lock.json'),
    JSON.stringify({ name: 'loomings', version: '2.6.5', lockfileVersion: 3, packages }),
  );

  return root;
}

describe('third-party notices generator', () => {
  it('includes production packages and excludes dev-only packages', () => {
    const root = createFixture();
    try {
      const notices = collectNotices(root);
      const rendered = renderNotices(notices);
      expect(notices.some((n) => n.name === 'prod-pkg' && n.version === '1.2.3' && n.license === 'MIT')).toBe(true);
      expect(notices.some((n) => n.name === 'dev-pkg')).toBe(false);
      expect(rendered).toContain('prod-pkg');
      expect(rendered).toContain('Copyright (c) Prod Pkg');
      expect(rendered).not.toContain('dev-pkg');
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  it('throws when a production package has no license text', () => {
    const root = createFixture({ includeMissingProd: true });
    try {
      expect(() => collectNotices(root)).toThrow(/missing-license-pkg/);
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  it('writes deterministic web and native notice files for a fixture', () => {
    const root = createFixture();
    try {
      const webPath = writeNotices('web', root);
      const nativePath = writeNotices('native', root);
      expect(webPath).toBe(join(root, 'public', 'licenses', 'THIRD-PARTY-NOTICES.txt'));
      expect(nativePath).toBe(join(root, 'macos', 'Resources', 'THIRD-PARTY-NOTICES.txt'));
      expect(existsSync(webPath)).toBe(true);
      expect(existsSync(nativePath)).toBe(true);
      expect(readFileSync(webPath, 'utf8')).toBe(readFileSync(nativePath, 'utf8'));
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  it('collects project, vendored design, font, and CPAL notices for the real repository', () => {
    const notices = collectNotices(REPO_ROOT);
    const rendered = renderNotices(notices);

    expect(notices.length).toBeGreaterThan(40);
    for (const notice of notices) {
      expect(notice.name).toBeTruthy();
      expect(notice.version).toBeTruthy();
      expect(notice.license).toBeTruthy();
      expect(notice.text.trim().length).toBeGreaterThan(0);
    }

    expect(rendered).toContain('loomings');
    expect(rendered).toContain('Copyright (c) 2026 Tiago Jacinto');
    expect(rendered).toContain('@tiagojct/tryworks-design');
    expect(rendered).toContain('citeproc');
    expect(rendered).toContain('@codemirror/view');
    expect(rendered).toContain('markdown-it');
    expect(rendered).toContain('Common Public Attribution License Version 1.0 (CPAL)');
    expect(rendered).toContain('The Literata Project Authors');
    expect(rendered).toContain('The Atkinson Hyperlegible Next Project Authors');
    expect(rendered).toContain('The Atkinson Hyperlegible Mono Project Authors');
    expect(rendered).toContain('Braille Institute of America');
    expect(rendered).toContain('The JetBrains Mono Project Authors');
    expect(rendered).toContain('The Source Serif 4 Project Authors');
    expect(rendered).not.toContain('vitest');
    expect(rendered).not.toContain('happy-dom');
  });
});
