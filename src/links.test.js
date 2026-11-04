import { readFileSync } from 'node:fs';
import { describe, it, expect } from 'vitest';
import { linkFromPaste } from './links.js';

const cases = JSON.parse(readFileSync(
  new URL('../macos/Tests/LoomingsEditorTests/Fixtures/paste-links.json', import.meta.url),
  'utf8',
));

describe('paste a URL over a selection', () => {
  for (const c of cases) {
    it(c.name, () => {
      expect(linkFromPaste(c.selected, c.pasted, c.before)).toBe(c.link);
    });
  }
});
