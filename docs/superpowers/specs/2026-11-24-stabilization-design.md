# Loomings stabilization design

Date: 2026-11-24
Baseline: `main` at `746b80a`
Selected approach: Stabilization first. Rebase the pending native plan afterward.

## Intent

Prevent data loss, wrong-file writes, hangs, local-file disclosure, and release failures.
Preserve the existing editor behavior unless a fix requires a narrow change.

## Goals

- Bind every file handle to the document that opened it.
- Preserve edits made during any save operation.
- Serialize saves and isolate scratch drafts between tabs.
- Make document deletion atomic and truthful.
- Bound citation marker allocation and other untrusted-input work.
- Refuse unsupported native text encodings before a save can corrupt them.
- Block local image access from unsaved shared documents.
- Prevent history deletion from deadlocking the native app.
- Include document images in native PDF and print output.
- Publish only stable releases with complete license material.

## Non-goals

- Do not implement the proposed TUI.
- Do not add new editor features during stabilization.
- Do not perform a broad rewrite of `editor.js` or `EditorWindowController.swift`.
- Do not migrate the native package to Swift 6 during stabilization.
- Do not execute the seven pending native feature tasks until stabilization passes.
- Do not change remote-image policy or browser support without a separate decision.

## Constraints

- Preserve public APIs and existing document formats.
- Keep web and native citation rules aligned through shared fixtures.
- Add a regression test before each behavioral fix.
- Run web and native checks after each atomic work package.
- Do not commit `macos/plans/`.
- Keep native-only work separate from web release numbering.

## Approaches considered

### 1. Stabilization first

Fix critical defects before adding features. Rebase the pending native plan afterward.

Trade-off: The prevalidated native patches will need new context and test expectations.
Benefit: Data-safety and security defects receive priority.

### 2. Pending native plan first

Execute the seven prevalidated native tasks. Apply stabilization afterward.

Trade-off: Critical defects remain longer. New changes increase the stabilization surface.
Benefit: The existing task script keeps its exact baseline.

### 3. Stabilization only

Fix defects and defer the native feature plan.

Trade-off: The prepared native improvements remain unapplied.
Benefit: This option has the smallest scope.

The user selected approach 1.

## Work packages

### P0: Data safety and untrusted input

1. Bind picked, dropped, and launched file handles to their payload.
2. Adopt a handle only after the load confirmation succeeds.
3. Capture handles before permission awaits.
4. Serialize all saves through one queue.
5. Preserve edits made during Save As and browser Save.
6. Store scratch drafts per tab or session.
7. Delete browser document content and index entry in one transaction.
8. Replace citation marker scanning with a bounded one-pass allocation.
9. Refuse UTF-32 and BOMless UTF-16 input in the native codec.
10. Block local image paths from unsaved shared native documents.
11. Release the history lock with `defer`.
12. Resolve image attachments before native handout layout.

### P1: Release integrity

1. Accept only stable tags that match `package.json`.
2. Move `latest` only for stable releases.
3. Bundle project, vendor, dependency, and full citeproc licenses.
4. Set least-privilege CI permissions.
5. Pin GitHub Actions to full commit SHAs.
6. Build before running artifact tests.
7. Start the Docker image in CI and probe the app.
8. Mirror native resource directories instead of merging them.

### P2: Correctness and performance

1. Blank native frontmatter before editor and preview parsing.
2. Render nested native blocks through one recursive path.
3. Invalidate native preview cache for complete reference definitions.
4. Prevent overlapping URL and email link output.
5. Move native export work off the main actor.
6. Bound native image-loading concurrency and cancel stale results.
7. Reduce web preview and citation work on the main thread.
8. Bound one teaching request in flight plus one pending request.
9. Add web image and citation import limits.
10. Repair service-worker update and cache-write lifecycles.

### P3: Test and documentation hardening

1. Add browser integration tests for save, open, delete, share, and offline flows.
2. Add an app-level native test target where practical.
3. Run the native self-test in macOS CI.
4. Add coverage thresholds for critical modules.
5. Update README, PRODUCT, DESIGN, and ACCEPTANCE.
6. Remove or archive retired Tauri scripts.

## Acceptance criteria

- Canceled or failed Open never changes the active save target.
- Edits made during Save As or browser Save remain dirty and recoverable.
- Three simultaneous saves execute in order.
- One tab cannot clear another tab's scratch draft.
- Failed deletion never reports success.
- Citation marker allocation always terminates.
- Native unsupported encodings are refused before save.
- Unsaved shared documents cannot load absolute local images.
- History deletion failure cannot hold the store lock.
- Native PDF and print output include local and data images.
- Prerelease tags cannot move production `latest`.
- Web and native artifacts contain required license texts.
- `npm test`, `npm run typecheck`, and `npm run build` pass.
- `swift test --package-path macos` passes.
- The native self-test passes on an awake, unlocked Mac.

## Risk assessment

| Change area | Risk | Mitigation |
|---|---|---|
| File handles and saves | High | Deferred-write tests and a manual browser matrix. |
| Scratch and deletion | High | Multi-tab and partial-failure tests. |
| Native image trust | Medium | Shared-document fixtures and export tests. |
| Native codec | Medium | UTF-32, UTF-16, BOM, and NUL fixtures. |
| Preview rendering | High | Nested-block and cross-language HTML fixtures. |
| Service worker | Medium | Open-client update and quota-failure tests. |
| CI and releases | Medium | Pull-request image builds and stable-tag tests. |
| Pending native plan | High | Rebase patches and regenerate expected test counts. |

## Sequencing

Complete P0 before P1. Complete P1 before the next release tag.
Start P2 after P0 and P1 checks pass.
Run P3 throughout the stabilization work.

After stabilization, rebase `macos/plans/2026-11-09_improvements-1-7.md`.
Update its baseline, patch context, and expected self-test counts.
Re-run every task in order. Do not reuse the old counts without verification.
