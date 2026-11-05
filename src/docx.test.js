import { describe, it, expect } from 'vitest';
import { Window } from 'happy-dom';
import JSZip from 'jszip';
import { htmlToDocx } from './docx.js';
import { renderMarkdown } from './markdown.js';

const parse = (html) => new new Window().DOMParser().parseFromString(html, 'text/html');

async function files(html, options = {}) {
  const blob = await htmlToDocx(html, { parse, ...options });
  const zip = await JSZip.loadAsync(await blob.arrayBuffer());
  const read = async (name) => zip.file(name)?.async('string');
  return { zip, doc: await read('word/document.xml'), styles: await read('word/styles.xml'), numbering: await read('word/numbering.xml'), rels: await read('word/_rels/document.xml.rels') };
}

describe('htmlToDocx', () => {
  it('writes a valid package with the Word style ids', async () => {
    const { zip, doc, styles } = await files(renderMarkdown('# Title\n\nText with **bold** and *italic*.\n\n> quoted\n'));
    expect(zip.file('[Content_Types].xml')).toBeTruthy();
    expect(doc).toContain('w:pStyle w:val="Heading1"');
    expect(doc).toContain('w:pStyle w:val="Quote"');
    expect(doc).toMatch(/<w:b[ />]/);
    expect(doc).toMatch(/<w:i[ />]/);
    for (const id of ['Title', 'Heading1', 'Quote', 'Bibliography', 'SourceCode', 'Hyperlink']) {
      expect(styles).toContain(`w:styleId="${id}"`);
    }
  });

  it('makes lists, restarting each numbered list', async () => {
    const { doc, numbering } = await files(renderMarkdown('1. a\n2. b\n\ntext\n\n1. c\n\n- x\n  - y\n'));
    expect(doc).toContain('<w:numPr>');
    expect(numbering).toContain('w:numFmt');
    const ids = new Set([...doc.matchAll(/<w:numId w:val="(\d+)"/g)].map((m) => m[1]));
    expect(ids.size).toBe(3);
    expect(doc).toContain('<w:ilvl w:val="1"');
  });

  it('keeps links, code and tables', async () => {
    const md = '[site](https://example.org) and `code`\n\n```\nline 1\nline 2\n```\n\n| a | b |\n|---|---|\n| 1 | 2 |\n';
    const { doc, rels } = await files(renderMarkdown(md));
    expect(rels).toContain('https://example.org');
    expect(doc).toContain('w:pStyle w:val="SourceCode"');
    expect(doc).toContain('<w:tbl>');
    expect(doc).toContain('line 2');
  });

  it('does not make a link of an unsafe target', async () => {
    const { doc, rels } = await files('<p><a href="javascript:alert(1)">bad</a></p>');
    expect(rels).not.toContain('javascript:');
    expect(doc).toContain('bad');
  });

  it('formats a reference list with the Bibliography style', async () => {
    const html = '<p>Text<sup>1</sup></p><section class="references"><h2>References</h2>' +
      '<div class="csl-entry"><div class="csl-left-margin">1.</div><div class="csl-right-inline">Miller M. <i>Spirometry</i>. 2005.</div></div></section>';
    const { doc } = await files(html);
    expect(doc).toContain('w:pStyle w:val="Bibliography"');
    expect(doc).toContain('Miller M.');
    expect(doc).toContain('<w:tab/>');
    expect(doc).toContain('w:vertAlign w:val="superscript"');
  });

  it('adds the frontmatter title unless the text opens with it', async () => {
    const added = await files('<h1>Intro</h1>', { title: 'My paper' });
    expect(added.doc).toContain('w:pStyle w:val="Title"');
    const same = await files('<h1>My paper</h1>', { title: 'My paper' });
    expect(same.doc).not.toContain('w:pStyle w:val="Title"');
  });

  it('embeds an image and falls back to text when it cannot load', async () => {
    const png = Uint8Array.from(atob('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='), (c) => c.charCodeAt(0));
    const ok = await files('<p><img src="a.png" alt="dot"></p>', { loadImage: async () => ({ data: png, type: 'png', width: 1, height: 1 }) });
    expect(ok.zip.file(/word\/media\//).length).toBe(1);
    const miss = await files('<p><img src="a.png" alt="dot"></p>');
    expect(miss.doc).toContain('[image: dot]');
  });

  it('puts a mermaid svg through the image loader', async () => {
    let seen = null;
    const { doc } = await files('<pre class="mermaid"><svg aria-label="flow"><rect/></svg></pre>', { loadImage: async (s) => { seen = s; return null; } });
    expect(seen.svg).toContain('<svg');
    expect(doc).toContain('[flow]');
  });

  it('sets the language and page size', async () => {
    const { styles, doc } = await files('<p>Olá</p>', { lang: 'pt-PT', paper: 'letter' });
    expect(styles).toContain('pt-PT');
    expect(doc).toContain('w:w="12240"');
  });
});
