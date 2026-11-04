// Renders mermaid fences in a preview root with Pele. Pele loads on demand.

const CACHE_LIMIT = 64;
const SELECTOR = 'pre > code.language-mermaid';

/** @type {Map<string, {svg: string} | {error: string}>} */
const cache = new Map();

/** Thrown when the Pele module cannot load. The result is not cached. */
export class LoadError extends Error {}

/** @type {typeof import('pele/lazy') | undefined} */
let pele;

/**
 * @param {string} text
 * @returns {Promise<{svg: string}>}
 */
async function peleRender(text) {
  try {
    // Keep the module after the first load, so later updates do not wait for the loader.
    pele ??= await import('pele/lazy');
    return await pele.renderAsync(text, { links: false, images: false });
  } catch (err) {
    // A diagram chunk that fails to load rejects with a TypeError, not a PeleError.
    if (pele && err instanceof pele.PeleError) throw err;
    throw new LoadError(err instanceof Error ? err.message : String(err));
  }
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
  const misses = [];
  // Apply every cache hit before the first await, so an unchanged diagram
  // never shows its source while another diagram renders.
  for (const code of Array.from(root.querySelectorAll(SELECTOR))) {
    const result = cache.get(code.textContent ?? '');
    if (result) apply(code, result);
    else misses.push(code);
  }
  for (const code of misses) {
    const source = code.textContent ?? '';
    let result = cache.get(source);
    if (!result) {
      let loadFailed = false;
      try {
        const { svg } = await render(source);
        result = { svg };
      } catch (err) {
        result = { error: err instanceof Error ? err.message : String(err) };
        if (err instanceof LoadError) loadFailed = true;
      }
      if (!loadFailed) remember(source, result);
    }
    apply(code, result);
  }
}

/**
 * @param {Element} code
 * @param {{svg: string} | {error: string}} result
 */
function apply(code, result) {
  const pre = code.parentElement;
  if (!pre) return;
  const source = code.textContent ?? '';
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

/**
 * Renders the diagrams in an HTML string. A failed diagram keeps its source.
 * @param {string} html
 * @param {(text: string) => Promise<{svg: string}>} [render]
 * @returns {Promise<string>}
 */
export async function renderDiagramsInHtml(html, render) {
  if (!html.includes('language-mermaid')) return html;
  const template = document.createElement('template');
  template.innerHTML = html;
  await renderDiagrams(template.content, render);
  return template.innerHTML;
}

/**
 * The Pele series and critical colours as CSS declarations, from palette roles.
 * @param {Record<string, string>} p roles(): accent, heading, emphasis, code, marker, accentLight, accentDim, fgDim
 * @returns {string}
 */
export function peleSeriesCss(p) {
  const series = [p.accent, p.heading, p.emphasis, p.code, p.marker, p.accentLight, p.accentDim, p.fgDim];
  return series.map((c, i) => `--pele-series-${i + 1}: ${c};`).join(' ') + ` --pele-critical: ${p.emphasis};`;
}
