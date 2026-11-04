// Renders mermaid fences in a preview root with Pele. Pele loads on demand.

const CACHE_LIMIT = 64;
const SELECTOR = 'pre > code.language-mermaid';

/** @type {Map<string, {svg: string} | {error: string}>} */
const cache = new Map();

/** Thrown when the Pele module cannot load. The result is not cached. */
export class LoadError extends Error {}

/**
 * @param {string} text
 * @returns {Promise<{svg: string}>}
 */
async function peleRender(text) {
  /** @type {typeof import('pele/lazy')} */
  let pele;
  try {
    pele = await import('pele/lazy');
  } catch (err) {
    throw new LoadError(err instanceof Error ? err.message : String(err));
  }
  return pele.renderAsync(text, { links: false, images: false });
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
    let loadFailed = false;
    if (!result) {
      try {
        const { svg } = await render(source);
        result = { svg };
      } catch (err) {
        result = { error: err instanceof Error ? err.message : String(err) };
        if (err instanceof LoadError) loadFailed = true;
      }
      if (!loadFailed) remember(source, result);
    }
    for (const name of ['data-line', 'data-line-end']) {
      const value = code.getAttribute(name);
      if (value !== null) pre.setAttribute(name, value);
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
