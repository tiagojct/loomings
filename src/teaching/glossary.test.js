import { describe, it, expect } from 'vitest';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { EditorState } from '@codemirror/state';
import { markdown } from '@codemirror/lang-markdown';
import { ensureSyntaxTree } from '@codemirror/language';
import { explain, markerAt, frontmatterRange, KINDS } from './glossary.js';
import { Text } from '@codemirror/state';

const root = fileURLToPath(new URL('../../', import.meta.url));
const cases = JSON.parse(readFileSync(join(root, 'macos/Tests/LoomingsTeachingTests/Fixtures/glossary-cases.json'), 'utf8'));

function at(doc, pos) {
  const state = EditorState.create({ doc, extensions: [markdown()] });
  ensureSyntaxTree(state, state.doc.length, 1000);
  return markerAt(state, pos);
}

describe('marker glossary: shared cases', () => {
  it('has the native cases', () => expect(cases.length).toBeGreaterThanOrEqual(20));
  for (const item of cases) {
    it(`${item.kind} ${item.marker}`, () => {
      expect(explain(item.kind, item.marker)).toEqual({ title: item.title, body: item.body, lesson: item.lesson });
    });
  }

  it('explains every marker kind, and nothing for code content', () => {
    for (const kind of KINDS) expect(explain(kind, 'x')?.body, kind).toBeTruthy();
    expect(explain('codeBlockContent', 'x')).toBeNull();
    expect(explain('nonsense', 'x')).toBeNull();
  });

  it('names lessons that exist', () => {
    for (const item of cases) {
      if (item.lesson) expect(existsSync(join(root, 'lessons', item.lesson)), item.lesson).toBe(true);
    }
  });
});

describe('marker under a position', () => {
  it('finds heading marks, ATX and underline', () => {
    expect(at('## Title\n', 0)).toEqual({ kind: 'headingMarker', marker: '##', from: 0, to: 2 });
    expect(at('## Title\n', 1)?.marker).toBe('##');
    expect(at('Title\n===\n', 7)).toEqual({ kind: 'headingMarker', marker: '===', from: 6, to: 9 });
  });

  it('tells emphasis from strong, and finds inline code', () => {
    expect(at('*a* **b**\n', 0)?.kind).toBe('emphasisMarker');
    expect(at('*a* **b**\n', 5)).toEqual({ kind: 'strongMarker', marker: '**', from: 4, to: 6 });
    expect(at('Say `x` now\n', 4)?.kind).toBe('inlineCodeMarker');
  });

  it('finds fences, quotations, lists and task boxes', () => {
    expect(at('```js\nx\n```\n', 1)).toEqual({ kind: 'fencedCodeDelimiter', marker: '```', from: 0, to: 3 });
    expect(at('> said\n', 0)?.kind).toBe('blockQuoteMarker');
    expect(at('- a\n', 0)).toEqual({ kind: 'listMarker', marker: '- ', from: 0, to: 1 });
    expect(at('12. a\n', 1)?.marker).toBe('12. ');
    expect(at('- [ ] task\n', 3)).toEqual({ kind: 'listMarker', marker: '[ ]', from: 2, to: 5 });
    expect(at('- [x] done\n', 2)?.marker).toBe('[x]');
  });

  it('tells links from images, and finds rules, HTML and strikethrough', () => {
    expect(at('[a](b)\n', 0)?.kind).toBe('linkPunctuation');
    expect(at('![a](b)\n', 0)?.kind).toBe('imagePunctuation');
    expect(at('![a](b)\n', 4)?.kind).toBe('imagePunctuation');
    expect(at('Text\n\n---\n', 7)?.kind).toBe('thematicBreak');
    expect(at('a <b>x</b>\n', 3)?.kind).toBe('rawHTML');
    expect(at('a ~~gone~~ b\n', 2)).toEqual({ kind: 'strikethroughMarker', marker: '~~', from: 2, to: 4 });
  });

  it('treats the frontmatter as one marker', () => {
    expect(at('---\ntitle: x\n---\n\nText\n', 6)).toEqual({ kind: 'frontmatter', marker: '---', from: 0, to: 16 });
  });

  it('finds nothing in plain text or code', () => {
    expect(at('Plain words.\n', 3)).toBeNull();
    expect(at('```\n**x**\n```\n', 5)).toBeNull();
  });
});

describe('frontmatter range', () => {
  it('reads --- on line 1 and --- by line 50, as the native app', () => {
    expect(frontmatterRange(Text.of(['---', 'title: x', '---', '', 'Text']))).toEqual({ from: 0, to: 16 });
    expect(frontmatterRange(Text.of(['# No', '---']))).toBeNull();
    expect(frontmatterRange(Text.of(['---', 'never closed']))).toBeNull();
    expect(frontmatterRange(Text.of(['---', ...Array(49).fill('x'), '---']))).toBeNull();
    expect(frontmatterRange(Text.of(['---', ...Array(48).fill('x'), '---']))?.from).toBe(0);
  });
});
