// ========================================
// Loomings — bundled lessons
// Every lessons/NN-slug.md becomes an entry, ordered by its numeric
// prefix, titled by its first heading, and reachable as ?lesson=slug.
// ========================================

const files = import.meta.glob('../lessons/*.md', { query: '?raw', import: 'default', eager: true });

export const LESSONS = Object.entries(files)
  .map(([path, content]) => {
    const file = path.split('/').pop();
    const m = file.match(/^(\d+)-(.+)\.md$/);
    const heading = content.match(/^#\s+(.+)$/m);
    return {
      order: m ? parseInt(m[1], 10) : 999,
      slug: m ? m[2] : file.replace(/\.md$/, ''),
      title: heading ? heading[1].trim() : file,
      content,
    };
  })
  .sort((a, b) => a.order - b.order);

export function lessonBySlug(slug) {
  return LESSONS.find((l) => l.slug === slug) || null;
}
