import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vite';

// The citation code as one script for JavaScriptCore. A JSContext has only
// the language, so the banner adds the few globals that the libraries read.
// There is no `Console` in this console: @citation-js/core then uses it as it
// is and does not call `new console.Console(process.stderr)`. The stub for
// sync-fetch-undici removes the only users of TextEncoder and TextDecoder, so
// their stand-ins only exist for a library that tests for them.
const banner = `globalThis.process = { env: {}, versions: {} };
globalThis.console = { log() {}, info() {}, warn() {}, error() {}, debug() {} };
globalThis.TextEncoder ??= class TextEncoder { encode() { throw new Error('TextEncoder is not available.'); } };
globalThis.TextDecoder ??= class TextDecoder { decode() { throw new Error('TextDecoder is not available.'); } };
`;

// Output: the build folder that scripts/export-native-resources.mjs reads.
export default defineConfig({
  publicDir: false,
  clearScreen: false,
  resolve: { alias: { 'sync-fetch-undici': fileURLToPath(new URL('./src/citations/stub-fetch.js', import.meta.url)) } },
  build: {
    outDir: 'node_modules/.cache/loomings-citations',
    emptyOutDir: true,
    target: 'safari18',
    sourcemap: false,
    lib: {
      entry: fileURLToPath(new URL('./src/citations/native-entry.js', import.meta.url)),
      name: 'LoomingsCitations',
      formats: ['iife'],
      fileName: () => 'citations.js',
    },
    rolldownOptions: { output: { banner } },
  },
});
