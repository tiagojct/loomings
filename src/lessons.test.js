import { describe, it, expect } from 'vitest';
import { LESSONS, lessonBySlug } from './lessons.js';

describe('lessons', () => {
  it('bundles at least one lesson', () => {
    expect(LESSONS.length).toBeGreaterThan(0);
  });
  it('gives every lesson a unique slug, a title from its first heading, and an order', () => {
    const slugs = LESSONS.map((l) => l.slug);
    expect(new Set(slugs).size).toBe(slugs.length);
    for (const l of LESSONS) {
      expect(l.slug).toMatch(/^[a-z0-9-]+$/);
      expect(l.title).not.toMatch(/\.md$/);
      expect(l.order).toBeLessThan(999);
      expect(l.content, l.slug).toMatch(/^# /m);
    }
  });
  it('keeps lessons in numeric order', () => {
    const orders = LESSONS.map((l) => l.order);
    expect(orders).toEqual([...orders].sort((a, b) => a - b));
  });
  it('finds lessons by slug and returns null otherwise', () => {
    expect(lessonBySlug(LESSONS[0].slug)).toBe(LESSONS[0]);
    expect(lessonBySlug('no-such-lesson')).toBeNull();
  });
  it('never uses raw HTML, which the preview does not render', () => {
    for (const l of LESSONS) expect(l.content, l.slug).not.toMatch(/<[a-z!][^>]*>/i);
  });
});
