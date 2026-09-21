import { defineConfig } from 'vite';

export default defineConfig({
  root: 'src',
  publicDir: false,
  clearScreen: false,
  // The editor is served at /app behind nginx (see nginx.conf); the landing
  // page in docs/ owns the site root. Asset URLs are built against this.
  base: '/app/',
  server: {
    port: 1420,
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
