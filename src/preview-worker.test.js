import { afterEach, describe, expect, it, vi } from 'vitest';
import { citedHtml } from './citations/document.js';
import { renderPreview } from './markdown.js';

describe('preview worker', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.resetModules();
  });

  it('renders citation-aware preview HTML without changing its output', async () => {
    const postMessage = vi.fn();
    const self = { postMessage, onmessage: null };
    vi.stubGlobal('self', self);
    await import('./preview-worker.js');

    const source = '---\ntitle: Demo\n---\n# Heading\n\nA [@silva] and [bad](javascript:x).';
    const citationStart = source.indexOf('[@silva]');
    const report = {
      citations: [{
        from: citationStart,
        to: citationStart + 8,
        html: '(Silva 2020)',
        markdown: '(Silva 2020)',
        missing: [],
      }],
      bibliography: ['<div class="csl-entry">Silva 2020</div>'],
      bibliographyMarkdown: 'Silva 2020',
      library: [],
      notes: [],
      markdownSource: source,
    };
    const expected = citedHtml(source, report, renderPreview);

    self.onmessage({ data: { id: 7, source, report } });

    expect(postMessage).toHaveBeenCalledWith({ id: 7, html: expected });
    const html = postMessage.mock.calls[0][0].html;
    expect(html).toContain('data-line');
    expect(html).toContain('data-line-end');
    expect(html).toContain('(Silva 2020)');
    expect(html).not.toContain('href="javascript:');
  });

  it('returns malformed report errors without throwing', async () => {
    const postMessage = vi.fn();
    const self = { postMessage, onmessage: null };
    vi.stubGlobal('self', self);
    await import('./preview-worker.js');

    expect(() => self.onmessage({
      data: {
        id: 8,
        source: '# Heading\n\n[@silva]',
        report: { citations: null },
      },
    })).not.toThrow();

    expect(postMessage).toHaveBeenCalledTimes(1);
    expect(postMessage.mock.calls[0][0].id).toBe(8);
    expect(typeof postMessage.mock.calls[0][0].error).toBe('string');
  });
});
