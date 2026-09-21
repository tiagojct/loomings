import { readFileSync } from 'node:fs';
import { defineConfig } from 'vite';

const pkg = JSON.parse(readFileSync(new URL('./package.json', import.meta.url), 'utf8'));

// The editor is served at /app behind nginx (see nginx.conf); the landing
// page in docs/ owns the site root. Asset URLs, the manifest's scope and
// the service worker's precache list are all built against this.
const BASE = '/app/';

// Emits sw.js next to index.html with the build's version and the list of
// files it produced, so the worker can precache exactly this build.
function loomingsServiceWorker() {
  return {
    name: 'loomings-service-worker',
    apply: 'build',
    generateBundle(_options, bundle) {
      // index.html is written after this hook runs, so the shell URL is
      // added by hand; everything else is whatever this build produced.
      const assets = [BASE, ...Object.keys(bundle)
        .filter((f) => f !== 'sw.js' && f !== 'index.html')
        .map((f) => BASE + f)];
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
    rollupOptions: {
      input: 'src/index.html',
    },
  },
});
