import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { mirrorDirectory } from '../scripts/export-native-resources.mjs';

describe('native resource directory export', () => {
  it('copies current files and removes files absent from the source', () => {
    const root = mkdtempSync(join(tmpdir(), 'loomings-native-resources-'));
    const source = join(root, 'source');
    const destination = join(root, 'destination');
    mkdirSync(source, { recursive: true });
    mkdirSync(destination, { recursive: true });
    writeFileSync(join(source, 'current.csl'), 'current source');
    writeFileSync(join(destination, 'current.csl'), 'old destination');
    writeFileSync(join(destination, 'removed.csl'), 'removed from source');
    writeFileSync(join(destination, 'stale.json'), 'stale destination');

    try {
      mirrorDirectory(source, destination);

      expect(readFileSync(join(destination, 'current.csl'), 'utf8')).toBe('current source');
      expect(existsSync(join(destination, 'removed.csl'))).toBe(false);
      expect(existsSync(join(destination, 'stale.json'))).toBe(false);
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  it('keeps the previous destination when copying the source fails', () => {
    const root = mkdtempSync(join(tmpdir(), 'loomings-native-resources-'));
    const source = join(root, 'missing-source');
    const destination = join(root, 'destination');
    mkdirSync(destination, { recursive: true });
    writeFileSync(join(destination, 'existing.csl'), 'previous destination');

    try {
      expect(() => mirrorDirectory(source, destination)).toThrow();

      expect(readFileSync(join(destination, 'existing.csl'), 'utf8')).toBe('previous destination');
      expect(readdirSync(root)).toEqual(['destination']);
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });
});
