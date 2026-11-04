// Renders mermaid fences in a preview root with Pele. Pele loads on demand.

const CACHE_LIMIT = 64;
const SELECTOR = 'pre > code.language-mermaid';

/** @type {Map<string, {svg: string} | {error: string}>} */
const cache = new Map();

/**
 * @param {string} text
 * @returns {Promise<{svg: string}>}
 */
async function peleRender(text) {
  const { renderAsync } = await import('pele/lazy');
  return renderAsync(text, { links: false, images: false });
}

/** @param {string} key @param {{svg: string} | {error: string}} value */
function remember(key, value) {
  if (cache.size >= CACHE_LIMIT) {
    const oldest = cache.keys().next().value;
    if (oldest !== undefined) cache.delete(oldest);
  }
  cache.set(key, value);
}

/**
 * @param {ParentNode} root
 * @returns {boolean}
 */
export function hasDiagrams(root) {
  return root.querySelector(SELECTOR) !== null;
}

/**
 * @param {ParentNode} root
 * @param {(text: string) => Promise<{svg: string}>} [render]
 * @returns {Promise<void>}
 */
export async function renderDiagrams(root, render = peleRender) {
  const blocks = Array.from(root.querySelectorAll(SELECTOR));
  for (const code of blocks) {
    const pre = code.parentElement;
    if (!pre) continue;
    const source = code.textContent ?? '';
    let result = cache.get(source);
    if (!result) {
      try {
        const { svg } = await render(source);
        result = { svg };
      } catch (err) {
        result = { error: err instanceof Error ? err.message : String(err) };
      }
      remember(source, result);
    }
    if ('svg' in result) {
      pre.classList.add('mermaid');
      pre.innerHTML = result.svg;
    } else {
      pre.classList.add('mermaid-error');
      const src = document.createElement('code');
      src.textContent = source;
      const msg = document.createElement('p');
      msg.textContent = result.error;
      pre.replaceChildren(src, msg);
    }
  }
}
