import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { defineConfig } from 'vite';

const pkg = JSON.parse(readFileSync(new URL('./package.json', import.meta.url), 'utf8'));

// The editor is served at /app behind nginx (see nginx.conf); the landing
// page in docs/ owns the site root. Asset URLs, the manifest's scope and
// the service worker's precache list are all built against this.
const BASE = '/app/';

// Every file copied verbatim from public/ (manifest, icons, fonts), as
// paths relative to the app root. Vite writes those after the bundle, so the
// list comes from the source directory, not from `bundle`.
function listPublicFiles(dir, prefix = '') {
  const out = [];
  for (const entry of readdirSync(join(dir, prefix), { withFileTypes: true })) {
    const rel = prefix ? `${prefix}/${entry.name}` : entry.name;
    if (entry.isDirectory()) out.push(...listPublicFiles(dir, rel));
    else out.push(rel);
  }
  return out.sort();
}

// Emits sw.js next to index.html with the build's version and the list of
// files it produced, so the worker can precache exactly this build.
function loomingsServiceWorker() {
  /** @type {string} */
  let publicDir = '';
  return {
    name: 'loomings-service-worker',
    apply: 'build',
    configResolved(config) { publicDir = config.publicDir; },
    generateBundle(_options, bundle) {
      // index.html is written after this hook runs, so the shell URL is
      // added by hand; everything else is whatever this build produced, plus
      // the public files the app needs offline (fonts and icons included).
      const assets = [BASE, ...Object.keys(bundle)
        .filter((f) => f !== 'sw.js' && f !== 'index.html')
        .map((f) => BASE + f),
      ...(publicDir ? listPublicFiles(publicDir)
        .filter((f) => /\.(woff2|png|svg|webmanifest|ico)$/.test(f))
        .map((f) => BASE + f) : [])];
      const template = readFileSync(new URL('./src/sw-template.js', import.meta.url), 'utf8');
      this.emitFile({
        type: 'asset',
        fileName: 'sw.js',
        source: template
          .replaceAll('__VERSION__', pkg.version)
          .replaceAll('__ASSETS__', JSON.stringify(assets))
          .replaceAll('__BASE__', BASE),
      });
    },
  };
}

export default defineConfig({
  root: 'src',
  publicDir: '../public', // manifest + icons, copied verbatim to dist/
  clearScreen: false,
  base: BASE,
  plugins: [loomingsServiceWorker()],
  server: {
    port: 1420,
    strictPort: true,
    host: '127.0.0.1',
  },
  preview: {
    port: 4173,
    strictPort: true,
    host: '127.0.0.1',
  },
  build: {
    outDir: '../dist',
    emptyOutDir: true,
    target: 'safari14',
    sourcemap: false,
    // The largest chunk is CodeMirror itself (532 kB, 184 kB gzip), which
    // changes only on a dependency bump; warn above that, not at the default.
    chunkSizeWarningLimit: 600,
    // Vite 8 is Rolldown-based: manualChunks is gone, groups replace it.
    // Keeping CodeMirror and markdown-it in their own chunks means an app fix
    // no longer invalidates the whole 700 kB payload in every cache.
    rolldownOptions: {
      output: {
        codeSplitting: {
          groups: [
            { name: 'codemirror', test: /[\\/]node_modules[\\/]@(?:codemirror|lezer)[\\/]/ },
            { name: 'markdown', test: /[\\/]node_modules[\\/](?:markdown-it|linkify-it|mdurl|uc\.micro|entities)[\\/]/ },
          ],
        },
      },
    },
    rollupOptions: {
      input: 'src/index.html',
    },
  },
});
