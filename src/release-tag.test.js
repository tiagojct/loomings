import { describe, expect, it } from 'vitest';
import { assertStableRelease, stableReleaseVersion } from '../scripts/release-tag.mjs';

describe('release tag validation', () => {
  it('extracts the version from a stable release tag', () => {
    expect(stableReleaseVersion('v2.6.5')).toBe('2.6.5');
  });

  it.each(['v2.7.0-rc.1', 'v2.7.0-beta.1', 'v2.7'])(
    'rejects non-stable release tag %s',
    (refName) => {
      expect(stableReleaseVersion(refName)).toBeNull();
    },
  );

  it('accepts a stable tag matching package.json', () => {
    expect(() => assertStableRelease('v2.6.5', '2.6.5')).not.toThrow();
  });

  it('rejects a stable tag that differs from package.json', () => {
    expect(() => assertStableRelease('v2.7.0', '2.6.5')).toThrow();
  });

  it('rejects a prerelease tag even when its version matches package.json', () => {
    expect(() => assertStableRelease('v2.7.0-rc.1', '2.7.0')).toThrow();
  });
});
