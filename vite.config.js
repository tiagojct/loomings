import { defineConfig } from 'vite';

export default defineConfig({
  root: 'src',
  publicDir: false,
  clearScreen: false,
  server: {
    port: 1420,
    strictPort: true,
    host: '127.0.0.1',
  },
  envPrefix: ['VITE_', 'TAURI_'],
  build: {
    outDir: '../dist',
    emptyOutDir: true,
    target: 'safari14',
    minify: 'esbuild',
    sourcemap: false,
    rollupOptions: {
      input: 'src/index.html',
    },
  },
});
