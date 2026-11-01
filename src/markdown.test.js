import { describe, it, expect } from 'vitest';
import { stripFrontmatter, renderMarkdown, renderPreview, SAFE_URL } from './markdown.js';

describe('markdown and frontmatter', () => {
  it('strips YAML frontmatter at the start of a document', () => {
    const raw = `---\ntitle: "Hello World"\nauthor: Author Name\ndate: 2026-10-01\n---\n\n# Body Heading\n\nSome text.`;
    const stripped = stripFrontmatter(raw);
    expect(stripped).not.toContain('title: "Hello World"');
    expect(stripped).toContain('# Body Heading');
  });

  it('preserves exact newline count when stripping frontmatter so data-line remains synchronized', () => {
    const raw = `---\ntitle: "Metadata"\nauthor: Tiago\n---\n# Heading`;
    const stripped = stripFrontmatter(raw);
    const rawLines = raw.split('\n');
    const strippedLines = stripped.split('\n');
    expect(strippedLines.length).toBe(rawLines.length);
    // Heading is on index 4 (0: ---, 1: title, 2: author, 3: ---, 4: # Heading)
    expect(strippedLines[4]).toBe('# Heading');
  });

  it('does not strip horizontal rules in the middle of a document', () => {
    const raw = `# Title\n\nParagraph 1\n\n---\n\nParagraph 2`;
    expect(stripFrontmatter(raw)).toBe(raw);
    const rendered = renderMarkdown(raw);
    expect(rendered).toMatch(/<hr\b/);
  });

  it('handles CRLF line endings in frontmatter', () => {
    const raw = `---\r\ntitle: Windows\r\n---\r\n# Windows Heading`;
    const stripped = stripFrontmatter(raw);
    expect(stripped).not.toContain('title: Windows');
    expect(stripped).toContain('# Windows Heading');
  });

  it('never renders frontmatter as an <h2> or <hr> heading in output HTML', () => {
    const raw = `---\ntitle: "Secret Title"\nauthor: Jane Doe\n---\n\n# Main Title\n\nParagraph text.`;
    const html = renderMarkdown(raw);
    expect(html).not.toContain('<h2>');
    expect(html).not.toContain('Secret Title');
    expect(html).toMatch(/<h1[^>]*>Main Title<\/h1>/);
  });
});

describe('URL sanitization', () => {
  it('identifies safe and unsafe URLs correctly', () => {
    expect(SAFE_URL.test('https://example.com')).toBe(true);
    expect(SAFE_URL.test('http://example.com/doc')).toBe(true);
    expect(SAFE_URL.test('mailto:user@example.com')).toBe(true);
    expect(SAFE_URL.test('#heading-1')).toBe(true);
    expect(SAFE_URL.test('/app/index.html')).toBe(true);
    expect(SAFE_URL.test('./local.png')).toBe(true);

    expect(SAFE_URL.test('javascript:alert(1)')).toBe(false);
    expect(SAFE_URL.test('vbscript:msgbox')).toBe(false);
    expect(SAFE_URL.test('data:text/html,<script>alert(1)</script>')).toBe(false);
    expect(SAFE_URL.test('ftp://evil.com')).toBe(false);
  });

  it('neutralizes non-safe link URLs (e.g. ftp) to # and adds noopener noreferrer', () => {
    const raw = `[Safe](https://example.com) and [Ftp Link](ftp://evil.com/doc)`;
    const html = renderMarkdown(raw);
    expect(html).toContain('href="https://example.com"');
    expect(html).toContain('rel="noopener noreferrer"');
    expect(html).not.toContain('ftp://evil.com');
    expect(html).toContain('href="#"');
  });

  it('blocks dangerous javascript: links completely', () => {
    const raw = `[Malicious](javascript:alert(1))`;
    const html = renderMarkdown(raw);
    expect(html).not.toContain('<a href="javascript');
  });

  it('allows safe images and data:image URLs, sanitizing unsafe schemes to #', () => {
    const safeImg = `![Web Image](https://example.com/pic.png)`;
    const dataImg = `![Data Image](data:image/png;base64,iVBORw0KGgo=)`;
    const badImg = `![Bad Image](ftp://evil.com/pic.png)`;

    const htmlSafe = renderMarkdown(safeImg);
    expect(htmlSafe).toContain('src="https://example.com/pic.png"');

    const htmlData = renderMarkdown(dataImg);
    expect(htmlData).toContain('src="data:image/png;base64,iVBORw0KGgo="');

    const htmlBad = renderMarkdown(badImg);
    expect(htmlBad).toContain('src="#"');
    expect(htmlBad).not.toContain('ftp://');
  });

  it('stamps data-line attributes on block elements for scroll sync', () => {
    const raw = `# Title\n\nParagraph`;
    const html = renderMarkdown(raw);
    expect(html).toMatch(/<h1 data-line="0">/);
    expect(html).toMatch(/<p data-line="2">/);
  });

  it('stamps data-line-end on top-level blocks of the live preview only', () => {
    const raw = `# Title\n\nOne\ntwo\n\n- a\n- b\n`;
    const html = renderPreview(raw);
    expect(html).toMatch(/<h1 data-line="0" data-line-end="1">/);
    expect(html).toMatch(/<p data-line="2" data-line-end="4">/);
    expect(html).toMatch(/<ul data-line="5" data-line-end="7">/);
    expect(html).toMatch(/<li data-line="5">/);
    // Export and the native fixtures keep markdown-it's own output.
    expect(renderMarkdown(raw)).not.toContain('data-line-end');
  });
});
