// ========================================
// Loomings — Markdown rendering and sanitization
// Configures markdown-it with URL sanitization, block source line stamping,
// and frontmatter handling for preview and export.
// ========================================

import MarkdownIt from 'markdown-it';

export const SAFE_URL = /^(https?:|mailto:|#|\/|\.\/|\.\.\/)/i;

/**
 * Strips YAML frontmatter at the start of a document while preserving
 * exact line counts so data-line attributes stay synchronized with the editor.
 *
 * @param {string} text
 * @returns {string}
 */
export function stripFrontmatter(text) {
  if (!text) return '';
  return text.replace(/^---[ \t]*\r?\n([\s\S]*?)\r?\n---[ \t]*(?:\r?\n|$)/, (match) => {
    const lineCount = (match.match(/\n/g) || []).length;
    return '\n'.repeat(lineCount);
  });
}

/**
 * Creates and configures a markdown-it instance.
 *
 * @param {object} [options]
 * @returns {InstanceType<typeof MarkdownIt>}
 */
export function createMarkdownRenderer(options = {}) {
  const md = new MarkdownIt({
    html: false,
    linkify: true,
    typographer: true,
    breaks: false,
    ...options,
  });

  // Stamp block tokens with data-line for scroll sync and navigation
  md.core.ruler.push('source_lines', (state) => {
    for (const token of state.tokens) {
      if (token.map && token.nesting !== -1 && !token.hidden) {
        token.attrSet('data-line', String(token.map[0]));
      }
    }
  });

  // URL sanitization for links
  const defaultLinkOpen = md.renderer.rules.link_open || function (tokens, idx, opts, _, self) {
    return self.renderToken(tokens, idx, opts);
  };
  md.renderer.rules.link_open = function (tokens, idx, opts, env, self) {
    const token = tokens[idx];
    const hrefIdx = token.attrIndex('href');
    if (hrefIdx >= 0 && token.attrs) {
      const href = token.attrs[hrefIdx][1];
      if (!SAFE_URL.test(href)) token.attrs[hrefIdx][1] = '#';
    }
    token.attrSet('rel', 'noopener noreferrer');
    return defaultLinkOpen(tokens, idx, opts, env, self);
  };

  // URL sanitization for images
  const defaultImage = md.renderer.rules.image;
  md.renderer.rules.image = function (tokens, idx, opts, env, self) {
    const token = tokens[idx];
    const srcIdx = token.attrIndex('src');
    if (srcIdx >= 0 && token.attrs) {
      const src = token.attrs[srcIdx][1];
      if (!SAFE_URL.test(src) && !/^data:image\//i.test(src)) {
        token.attrs[srcIdx][1] = '#';
      }
    }
    // markdown-it always installs an image rule; the fallback keeps this
    // override safe if that ever stops being true.
    if (!defaultImage) return self.renderToken(tokens, idx, opts);
    return defaultImage(tokens, idx, opts, env, self);
  };

  return md;
}

export const defaultMd = createMarkdownRenderer();

/**
 * Renders markdown to HTML, stripping frontmatter so it is never
 * erroneously rendered as a heading or horizontal rule.
 *
 * @param {string} text
 * @returns {string}
 */
export function renderMarkdown(text) {
  return defaultMd.render(stripFrontmatter(text));
}
