import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { handoutCss, paperFor, oneAtATime, withWaitStatus } from './handout.js';
import { roles } from './palettes.js';

describe('handout page', () => {
  it('uses Letter where the native app does, A4 elsewhere', () => {
    expect(paperFor('en-US')).toBe('letter');
    expect(paperFor('en')).toBe('letter');
    expect(paperFor('en-GB')).toBe('A4');
    expect(paperFor('pt-PT')).toBe('A4');
    expect(paperFor('pt')).toBe('A4');
    expect(paperFor('not a locale')).toBe('A4');
  });

  it('numbers pages "Title · page N of M", with the title escaped', () => {
    const css = handoutCss({ title: 'A "quoted" \\ title\nnext', palette: roles('pequod', 'light'), paper: 'A4' });
    expect(css).toContain('size: A4;');
    expect(css).toContain('content: "A \\"quoted\\" \\\\ title next \\00B7  page " counter(page) " of " counter(pages);');
    expect(handoutCss({ title: '', palette: roles('pequod', 'light'), paper: 'letter' }))
      .toContain('content: "page " counter(page) " of " counter(pages);');
  });

  it("prints in the family's light colours", () => {
    const p = roles('pequod', 'light');
    const css = handoutCss({ title: 'T', palette: p, paper: 'A4' });
    expect(css).toContain(`--print-fg: ${p.fg};`);
    expect(css).toContain(`--print-heading: ${p.heading};`);
    expect(css).toContain(`--print-link: ${p.accent};`);
    expect(css).toMatch(/@media print \{ :root \{/);
  });

  it('maps the diagram colours to the light palette for print', () => {
    const p = roles('pequod', 'light');
    const css = handoutCss({ title: 'T', palette: p, paper: 'A4' });
    expect(css).toContain('--pele-bg: #fff;');
    expect(css).toContain(`--pele-fg: ${p.fg};`);
    expect(css).toContain(`--pele-line: ${p.fgDim};`);
    expect(css).toContain(`--pele-surface: ${p.bgElev};`);
    expect(css).toContain(`--pele-surface-alt: ${p.bgDeep};`);
    expect(css).toContain(`--pele-border: ${p.border};`);
    expect(css).toContain(`--pele-accent: ${p.accent};`);
    expect(css).toContain(`--pele-series-2: color-mix(in srgb, ${p.fg} 72%, #fff);`);
    expect(css).toContain(`--pele-critical: ${p.accent};`);
  });
});

describe('oneAtATime', () => {
  it('ignores a call while the first one runs, and takes a call after it', async () => {
    let finish = () => {};
    const task = vi.fn(() => new Promise((resolve) => { finish = resolve; }));
    const once = oneAtATime(task);
    const first = once();
    await once();
    expect(task).toHaveBeenCalledTimes(1);
    finish();
    await first;
    once();
    expect(task).toHaveBeenCalledTimes(2);
  });

  it('takes a new call after a task that fails', async () => {
    const task = vi.fn().mockRejectedValueOnce(new Error('no')).mockResolvedValue('ok');
    const once = oneAtATime(task);
    await expect(once()).rejects.toThrow('no');
    await expect(once()).resolves.toBe('ok');
  });
});

describe('withWaitStatus', () => {
  beforeEach(() => { vi.useFakeTimers(); });
  afterEach(() => { vi.useRealTimers(); });

  it('shows nothing for a short wait', async () => {
    const show = vi.fn();
    const hide = vi.fn();
    await expect(withWaitStatus(Promise.resolve('x'), show, hide)).resolves.toBe('x');
    await vi.advanceTimersByTimeAsync(1000);
    expect(show).not.toHaveBeenCalled();
    expect(hide).not.toHaveBeenCalled();
  });

  it('shows the status during a long wait and removes it after', async () => {
    const show = vi.fn();
    const hide = vi.fn();
    let finish = () => {};
    const waited = withWaitStatus(new Promise((resolve) => { finish = resolve; }), show, hide);
    await vi.advanceTimersByTimeAsync(150);
    expect(show).toHaveBeenCalledTimes(1);
    expect(hide).not.toHaveBeenCalled();
    finish();
    await waited;
    expect(hide).toHaveBeenCalledTimes(1);
  });
});
