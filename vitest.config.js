import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  // citation-js reads sync-fetch-undici; the app has no network path.
  resolve: { alias: { 'sync-fetch-undici': fileURLToPath(new URL('./src/citations/stub-fetch.js', import.meta.url)) } },
  test: {
    environment: 'node',
    include: ['src/**/*.test.js'],
  },
});
