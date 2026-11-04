// @vitest-environment happy-dom
import { describe, it, expect, vi, beforeEach } from 'vitest';

/** @param {string} html */
function root(html) {
  const el = document.createElement('div');
  el.innerHTML = html;
  return el;
}

import { renderPreview } from './markdown.js';

/** Real preview markup for a mermaid fence. @param {string} src */
const fence = (src) =>
  renderPreview('```mermaid\n' + src.replace(/&gt;/g, '>').replace(/&lt;/g, '<') + '\n```');

/** @type {typeof import('./mermaid.js')} */
let m;
beforeEach(async () => {
  vi.resetModules();
  vi.doUnmock('pele/lazy');
  m = await import('./mermaid.js');
});

describe('mermaid renderer', () => {
  it('replaces a mermaid fence with its svg and keeps data-line', async () => {
    const el = root(fence('graph TD; A--&gt;B'));
    expect(m.hasDiagrams(el)).toBe(true);
    await m.renderDiagrams(el, async () => ({ svg: '<svg id="d"></svg>' }));
    const pre = el.querySelector('pre');
    expect(pre?.getAttribute('data-line')).toBe('0');
    expect(pre?.hasAttribute('data-line-end')).toBe(true);
    expect(pre?.classList.contains('mermaid')).toBe(true);
    expect(pre?.querySelector('svg#d')).not.toBeNull();
    expect(pre?.querySelector('code')).toBeNull();
  });

  it('leaves other code blocks alone', async () => {
    const html = '<pre data-line="1"><code class="language-js">let a;</code></pre>';
    const el = root(html);
    expect(m.hasDiagrams(el)).toBe(false);
    const render = vi.fn();
    await m.renderDiagrams(el, render);
    expect(render).not.toHaveBeenCalled();
    expect(el.innerHTML).toBe(html);
  });

  it('shows the source and the error as text for a diagram that fails', async () => {
    const el = root(fence('bad source'));
    await m.renderDiagrams(el, async () => {
      throw new Error('<b>x</b>');
    });
    const pre = el.querySelector('pre');
    expect(pre?.classList.contains('mermaid-error')).toBe(true);
    expect(pre?.getAttribute('data-line')).toBe('0');
    expect(pre?.hasAttribute('data-line-end')).toBe(true);
    expect(pre?.querySelector('code')?.textContent).toBe('bad source\n');
    expect(pre?.querySelector('p')?.textContent).toContain('<b>x</b>');
    expect(el.querySelector('b')).toBeNull();
  });

  it('does not call render twice for the same source', async () => {
    const render = vi.fn(async () => ({ svg: '<svg></svg>' }));
    await m.renderDiagrams(root(fence('graph TD; A--&gt;B')), render);
    await m.renderDiagrams(root(fence('graph TD; A--&gt;B')), render);
    expect(render).toHaveBeenCalledTimes(1);
  });

  it('does not cache a failed module load', async () => {
    const src = 'graph TD; A--&gt;B';
    const el = root(fence(src));
    await m.renderDiagrams(el, async () => {
      throw new m.LoadError('chunk failed');
    });
    expect(el.querySelector('pre')?.classList.contains('mermaid-error')).toBe(true);
    const again = root(fence(src));
    await m.renderDiagrams(again, async () => ({ svg: '<svg id="ok"></svg>' }));
    expect(again.querySelector('svg#ok')).not.toBeNull();
  });

  it('passes links false and images false', async () => {
    const renderAsync = vi.fn(async () => ({ svg: '<svg></svg>' }));
    vi.doMock('pele/lazy', () => ({ renderAsync }));
    vi.resetModules();
    const fresh = await import('./mermaid.js');
    await fresh.renderDiagrams(root(fence('graph TD; A--&gt;B')));
    expect(renderAsync).toHaveBeenCalledWith('graph TD; A-->B\n', {
      links: false,
      images: false,
    });
  });

  it('a hostile label produces no script element', async () => {
    const el = root(
      fence('graph TD\n A["&lt;script&gt;alert(1)&lt;/script&gt;&lt;img src=x onerror=alert(1)&gt;"] --&gt; B'),
    );
    await m.renderDiagrams(el);
    expect(el.querySelector('svg')).not.toBeNull();
    expect(el.querySelector('script')).toBeNull();
    expect(el.querySelector('[onerror]')).toBeNull();
  });
});
