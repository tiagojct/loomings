# Web preview worker design

Date: 2026-11-27

## Intent

The live preview renders Markdown on the browser main thread. A large document can therefore pause typing, scrolling, and input handling. Citations already run in a worker. The preview should use the same separation.

This design moves live preview rendering to a worker. It preserves the current HTML, citation behavior, source mapping, diagrams, scroll sync, exports, and print output.

## Goals

- Render live preview HTML outside the main thread.
- Keep at most one active render and one pending render.
- Apply only the newest requested result.
- Preserve byte-for-byte preview HTML.
- Keep the previous preview visible while a new result waits.
- Fall back to main-thread rendering when a worker cannot run.
- Keep export and print behavior unchanged.

## Non-goals

- Incremental block rendering.
- Changes to teaching or citation request scheduling.
- Changes to native preview code.
- Visual or CSS changes.
- Changes to document formats or public web APIs.
- Web release-number changes.

## Constraints

- The app targets Safari 14 and uses Vite 8.
- The strict CSP already permits workers from the same origin.
- The service worker precaches every emitted bundle asset.
- `renderPreview` remains a pure exported function for tests and native fixture parity.
- `npm run typecheck` stays clean under `checkJs` and `strictNullChecks`.
- No network requests are added.

## Current behavior

`src/editor.js` waits 150 ms after an edit. It then calls `citedHtml` and `renderPreview` synchronously. The function writes `preview.innerHTML`, invalidates paired blocks, synchronizes scroll, and starts diagram rendering.

Citation reports call the same path with `onlyIfChanged`. That path compares rendered HTML before replacing the DOM.

Print and export call `renderPreview` or `renderMarkdown` directly. Those paths stay on the main thread.

## Approaches considered

### 1. Dedicated preview worker with latest-only delivery

Chosen.

A worker owns the Markdown renderer. A small client allows one active request and one pending request. A newer request replaces the pending one. A stale active result is discarded. The main thread only applies the newest HTML.

This gives the largest responsiveness improvement. It adds a worker lifecycle and a fallback path.

### 2. Bound teaching and citation queues first

This would prevent analysis backlogs with a smaller change. It would not move preview rendering off the main thread. The user selected approach 1.

### 3. Incremental main-thread block rendering

This could reuse unchanged blocks. It would still perform Markdown work on the main thread. It also requires a larger cache design. The user selected approach 1.

## Design

### Worker

Create `src/preview-worker.js`.

It imports `citedHtml` and `renderPreview`. It receives `{id, source, report}`. It returns `{id, html}`. It catches render errors and returns `{id, error}` without terminating the worker.

The worker has no DOM access and no persistent document state.

### Client

Create `src/preview-client.js`.

Export `createPreviewClient({spawn, fallback})`. The default spawn creates a module worker. The default fallback calls `citedHtml(source, report, renderPreview)`.

The client exposes:

- `render(source, report)`: returns `Promise<string|null>`.
- `reset()`: drops active and pending requests and terminates the worker.

`null` means a newer request superseded the result, or rendering failed. The caller keeps its previous preview.

The client starts the worker on first use. It keeps one active request. A second request replaces the pending request and resolves the replaced promise with `null`.

When the active result arrives, the client discards it if a newer request exists. It then starts the pending request. Otherwise it resolves the active promise with the HTML.

A render-error answer resolves `null` for that request. It does not use the main-thread fallback, because the same deterministic render would fail again. The worker stays alive for later requests.

If worker startup fails, the client uses the fallback for the latest request. If a running worker fails, the client terminates it, drops stale results, and uses the fallback for the latest request. It does not repeatedly restart a broken worker.

### Editor integration

`updatePreview` captures the current text and citation report. It increments `previewGeneration` before calling the client. It awaits the returned HTML.

The editor applies the HTML only when all conditions hold:

- The promise returned HTML.
- `previewGeneration` still matches the captured generation.
- The preview is still shown.

The editor then performs the existing DOM update, pairing invalidation, scroll sync, and diagram rendering. The `onlyIfChanged` comparison moves after the worker result. Identical HTML causes no DOM replacement.

A worker result never overwrites the print handout. The print path already increments `previewGeneration` before it writes the page.

The 150 ms edit debounce stays unchanged. Export and print keep their direct renderer calls.

### Failure behavior

Worker lifecycle errors do not surface as unhandled rejections. The fallback renders only the latest request. If the fallback also fails, the promise resolves `null`. The previous preview stays visible.

A render-error answer follows the same visible result: the promise resolves `null`, and the previous preview stays visible. It does not retry on the main thread.

No loading spinner or blank state is added. The first worker render may take longer than later renders.

## Data flow

1. An edit schedules `updatePreview` after 150 ms.
2. The editor captures text, report, and generation.
3. The client sends the request to the worker or coalesces it.
4. The worker returns HTML for that request.
5. The client resolves only the newest request.
6. The editor checks generation and visibility.
7. The editor updates the DOM and starts diagrams.

## Tests

Add `src/preview-worker.test.js`:

- A message returns HTML identical to `citedHtml(source, report, renderPreview)`.
- Frontmatter, source lines, citation output, and URL sanitization survive the worker path.
- A render error returns an error message without terminating the worker.

Add `src/preview-client.test.js` with a fake worker:

- The worker starts on first use only.
- Two rapid requests produce one active and one pending message.
- A third request replaces the pending request.
- A superseded active result resolves `null`.
- The newest result resolves with HTML.
- A render error resolves `null`, keeps the worker alive, and does not call the fallback.
- Startup failure uses the fallback.
- Runtime worker failure uses the latest fallback and ignores late answers.
- `reset` terminates the worker and resolves waiting requests with `null`.

Keep `src/markdown.test.js` and citation tests unchanged. They continue to define output parity.

Run:

```sh
npm test
npm run typecheck
npm run build
node macos/scripts/render-web-fixtures.mjs
git diff --exit-code -- macos/Tests/LoomingsPreviewTests/Fixtures
swift test --package-path macos --filter PreviewHTMLTests
```

The build must emit the preview worker asset. The service worker asset list must include it.

## Risks and mitigations

- **Worker startup latency:** Keep the previous preview until the first result arrives.
- **Stale results:** Use request ids and editor generations.
- **Worker queue growth:** Allow one active and one pending request only.
- **Browser worker failure:** Use the existing synchronous renderer as fallback.
- **Offline worker chunk:** Rely on the existing service-worker precache of emitted assets.
- **Duplicate renderer memory:** Accept one renderer in the worker. The main renderer remains for print and export.

## Success criteria

- Live preview rendering does not run on the main thread when the worker is available.
- Rapid edits create at most one active and one pending worker request.
- Stale results never replace newer preview HTML.
- Preview HTML remains byte-for-byte identical.
- Citations, diagrams, pairing, and scroll sync keep their current behavior.
- Print and export output remains unchanged.
- All verification commands pass.

## Approval

The user selected approach 1. Implementation waits for approval of this design.
