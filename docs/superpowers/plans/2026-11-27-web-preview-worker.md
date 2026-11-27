# Web Preview Worker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move live preview rendering off the browser main thread without changing preview output or user-visible behavior.

**Architecture:** A dedicated worker renders citation-aware preview HTML. A client coalesces requests to one active and one pending render. The editor applies only the newest result and keeps synchronous export and print paths.

**Tech Stack:** Plain JavaScript, Vite 8, Web Workers, markdown-it, Vitest, TypeScript `checkJs`.

**Spec:** `docs/superpowers/specs/2026-11-27-web-preview-worker-design.md`

## Global Constraints

- Preserve public APIs unless a task explicitly extends them.
- Add a regression test before each behavioral fix.
- Keep web and native citation rules aligned through shared fixtures.
- Preserve byte-for-byte parity with existing web HTML fixtures.
- Keep native-only work separate from web release numbering.
- Do not commit `macos/plans/`.
- Do not change `package.json` version numbers.
- Keep `npm run typecheck` clean.
- Add no network requests.
- Use no emojis in code, comments, tests, documentation, or commit messages.

## Review Focus

- Rapid edits must produce one active and one pending worker request at most. Task 2 pins this with a fake worker.
- A superseded active result must resolve `null` and never reach the editor. Task 2 pins this with out-of-order answers.
- Worker startup failure must render the latest request through the fallback. Task 2 pins this with a throwing spawn.
- A running worker failure must terminate the worker, ignore late answers, and use the latest fallback. Task 2 pins this with a fake `onerror`.
- A deterministic render error must resolve `null`, keep the worker alive, and skip the fallback. Tasks 1 and 2 pin the worker reply and client behavior.

---

### Task 1: Render preview HTML in a worker

**Files:**
- Create: `src/preview-worker.js`
- Create: `src/preview-worker.test.js`

**Interfaces:**
- Consumes: `citedHtml(source, report, renderPreview)` from `src/citations/document.js`.
- Consumes: `renderPreview(text)` from `src/markdown.js`.
- Produces: worker input `{id: number, source: string, report: import('./citations/session.js').CitationReport|null}`.
- Produces: worker output `{id: number, html: string}` or `{id: number, error: string}`.

- [ ] **Step 1: Write the failing worker tests**

Create `src/preview-worker.test.js` with a fake `self` object, following `src/citations/worker.test.js`.

Test exact parity:

```js
const source = '---\ntitle: Demo\n---\n# Heading\n\nA [@silva] and [bad](javascript:x).';
const report = {
  citations: [{ from: source.indexOf('[@silva]'), to: source.indexOf('[@silva]') + 8,
    html: '(Silva 2020)', markdown: '(Silva 2020)', missing: [] }],
  bibliography: ['<div class="csl-entry">Silva 2020</div>'],
  bibliographyMarkdown: 'Silva 2020',
  library: [], notes: [], markdownSource: source,
};
const expected = citedHtml(source, report, renderPreview);
```

Send `{id: 7, source, report}`. Assert the reply equals `{id: 7, html: expected}`. Assert the HTML contains `data-line`, `data-line-end`, `(Silva 2020)`, and no `javascript:` URL.

Add a second test. Send a malformed report with `citations: null`. Assert the reply has the same id, a string `error`, and no thrown exception. Reset modules between tests.

- [ ] **Step 2: Run the worker tests and verify failure**

Run: `npx vitest run src/preview-worker.test.js`
Expected: FAIL because `src/preview-worker.js` does not exist.

- [ ] **Step 3: Implement the worker message handler**

Create `src/preview-worker.js`. Import `citedHtml` and `renderPreview`. Assign `self.onmessage`. Return the exact success and error message shapes defined in Interfaces. Convert caught errors to a string. Do not access the DOM. Do not terminate the worker after a render error.

- [ ] **Step 4: Run the worker tests and verify success**

Run: `npx vitest run src/preview-worker.test.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/preview-worker.js src/preview-worker.test.js
git commit -m "feat: render web preview in a worker"
```

---

### Task 2: Coalesce preview requests and contain worker failures

**Files:**
- Create: `src/preview-client.js`
- Create: `src/preview-client.test.js`

**Interfaces:**
- Consumes: the Task 1 worker message contract.
- Produces: `createPreviewClient(options)`.
- Produces: `render(source: string, report: CitationReport|null): Promise<string|null>`.
- Produces: `reset(): void`.
- Options: `spawn?: () => Worker`, `fallback?: (source: string, report: CitationReport|null) => string`.

- [ ] **Step 1: Write the failing client tests**

Create a fake worker with `sent`, `onmessage`, `onerror`, `postMessage`, `terminate`, and `answer(id, data)`.

Test lazy startup:

```js
const spawn = vi.fn(fakeWorker);
const client = createPreviewClient({ spawn });
expect(spawn).not.toHaveBeenCalled();
client.render('a', null);
expect(spawn).toHaveBeenCalledTimes(1);
```

Test one active and one pending request:

```js
const first = client.render('a', null);
client.render('b', null);
const third = client.render('c', null);
expect(w.sent.map((m) => m.source)).toEqual(['a']);
w.answer(w.sent[0].id, { id: w.sent[0].id, html: 'A' });
expect(w.sent.map((m) => m.source)).toEqual(['a', 'c']);
await expect(first).resolves.toBeNull();
```

Answer the second request and assert `third` resolves with its HTML.

Test out-of-order delivery. Answer the active request after a newer request exists. Assert the active promise resolves `null` and the pending request starts.

Test startup failure. Use `spawn: () => { throw new Error('no worker'); }` and a fallback spy. Assert the latest request resolves through the fallback.

Test runtime failure. Start an active request for `a` and a pending request for `b`, then call `w.onerror()`. Assert `terminate` was called. Assert the active promise resolves `null` and the pending promise resolves the fallback HTML for `b`. Send a late answer and assert it changes nothing.

Test render errors. Answer with `{id, error: 'bad render'}`. Assert the promise resolves `null`, the fallback was not called, and the worker was not terminated.

Test reset. Start active and pending requests, call `reset()`, and assert both promises resolve `null`. Assert `terminate` was called once.

- [ ] **Step 2: Run the client tests and verify failure**

Run: `npx vitest run src/preview-client.test.js`
Expected: FAIL because `src/preview-client.js` does not exist.

- [ ] **Step 3: Implement the preview client**

Create `src/preview-client.js` with the exact interface from the Interfaces block.

Use a request id, one `active` request, and one `pending` request. Replace a pending request and resolve its old promise with `null`. Start the worker lazily. Ignore answers whose id is not active.

Resolve a stale active promise with `null` when a newer request exists. Resolve the newest active promise with HTML otherwise.

Treat startup failure and `onerror` as worker lifecycle failures. Use the fallback for the latest request. Set the worker unavailable after a lifecycle failure. Ignore late answers.

Treat `{id, error}` as a render failure. Resolve `null`, keep the worker alive, and do not call the fallback.

Make `reset()` drop both request slots, resolve their promises with `null`, and terminate the worker. The default fallback calls `citedHtml(source, report, renderPreview)`.

- [ ] **Step 4: Run the client tests and verify success**

Run: `npx vitest run src/preview-client.test.js`
Expected: PASS.

- [ ] **Step 5: Run typechecking and commit**

Run: `npm run typecheck`
Expected: PASS.

```bash
git add src/preview-client.js src/preview-client.test.js
git commit -m "feat: coalesce web preview worker requests"
```

---

### Task 3: Apply only the newest worker result in the editor

**Files:**
- Modify: `src/editor.js:12,47,1598-1623`
- Modify: `src/boot-safari.test.js:44-58`
- Test: `src/preview-client.test.js`
- Test: `src/preview-worker.test.js`
- Test: `src/sw.test.js:164-174`

**Interfaces:**
- Consumes: `createPreviewClient()` and `render(source, report)` from Task 2.
- Consumes: existing `previewGeneration`, `previewHtml`, `previewShown`, pairing, scroll, and diagram helpers.
- Produces: asynchronous `updatePreview({onlyIfChanged?: boolean})` with unchanged call sites.

- [ ] **Step 1: Add the boot-boundary regression test**

In `src/boot-safari.test.js`, extend the first boot-module test:

```js
expect(modules).toContain(join(here, 'preview-client.js'));
expect(modules).not.toContain(join(here, 'preview-worker.js'));
```

Run: `npx vitest run src/boot-safari.test.js`
Expected: FAIL because the editor does not import the preview client.

- [ ] **Step 2: Import and create the preview client**

In `src/editor.js`, import `createPreviewClient` from `./preview-client.js`. Create one module-level `previewClient` before `updatePreview`. Keep the existing `renderPreview` import for print and fallback compatibility.

- [ ] **Step 3: Make `updatePreview` asynchronous and generation-safe**

Keep `applyReferencesView()` and the `previewShown()` guard first. Capture `text`, `citations.reportFor(text)`, and `const generation = ++previewGeneration` before calling `previewClient.render(text, report)`.

Await the result. Return when the result is `null`, the generation changed, or the preview is no longer shown. Apply the existing `onlyIfChanged` comparison after the await. Then perform the existing DOM replacement, pairing invalidation, scroll sync, and diagram rendering. Keep the diagram generation check.

Do not change `schedulePreview` or its 150 ms delay. Do not change export or print renderer calls. The print path continues to increment `previewGeneration` before writing the handout.

- [ ] **Step 4: Run focused tests and typechecking**

Run:

```sh
npx vitest run src/boot-safari.test.js src/preview-worker.test.js src/preview-client.test.js src/markdown.test.js
npm run typecheck
```

Expected: PASS.

- [ ] **Step 5: Build and verify the worker asset and precache**

Run:

```sh
npm run build
find dist/assets -maxdepth 1 -name 'preview-worker-*.js'
npm test
```

Expected: the build succeeds, the find command prints one preview worker asset, and all tests pass. The existing built-precache test must include the worker asset.

- [ ] **Step 6: Verify native fixture parity and Swift preview tests**

Run:

```sh
node macos/scripts/render-web-fixtures.mjs
git diff --exit-code -- macos/Tests/LoomingsPreviewTests/Fixtures
swift test --package-path macos --filter PreviewHTMLTests
git diff --check
```

Expected: 12 fixtures render, the fixture diff is empty, Swift preview tests pass, and whitespace checks are clean.

- [ ] **Step 7: Commit**

```bash
git add src/editor.js src/boot-safari.test.js
git commit -m "feat: apply latest web preview worker result"
```

---

## Final verification

- [ ] Run `npm test`.
- [ ] Run `npm run typecheck`.
- [ ] Run `npm run build`.
- [ ] Confirm the build emits one `preview-worker-*.js` asset.
- [ ] Confirm `src/sw.test.js` includes that asset in the built precache list.
- [ ] Run `node macos/scripts/render-web-fixtures.mjs`.
- [ ] Confirm `git diff --exit-code -- macos/Tests/LoomingsPreviewTests/Fixtures`.
- [ ] Run `swift test --package-path macos --filter PreviewHTMLTests`.
- [ ] Run `git diff --check`.
- [ ] Review the branch for stale-result, fallback, print-race, and offline-worker regressions.
