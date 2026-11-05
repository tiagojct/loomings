# Mermaid on the Web Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show `mermaid` code fences as diagrams in the web preview, print and HTML export.

**Architecture:** `src/mermaid.js` finds `pre > code.language-mermaid` in rendered HTML and replaces the content of the `pre` with SVG from `pele/lazy`. The `pre` keeps its `data-line` attributes, so scroll sync and paired lines keep working. `renderMarkdown` and `renderPreview` do not change.

**Tech Stack:** pele 1.x, Vitest with happy-dom.

**Spec:** `docs/superpowers/specs/2026-11-04-citations-and-diagrams.md`, section Mermaid.

## Global Constraints

- Web only. No file under `macos/` changes, and no HTML fixture changes.
- Colours only through existing palette variables. No new hex.
- Always pass `links: false` and `images: false`. Show errors with `textContent`.
- The pele code loads only when a document has a mermaid fence.
- No Claude author, co-author or session lines in commits. Follow CLAUDE.md for STE and European Portuguese.

## Review Focus

1. A diagram typed by hand is invalid most of the time: the preview shows the source and the error, and the next valid state replaces them.
2. Each keystroke replaces the whole preview: an unchanged diagram must come from a cache, with no flicker and no second parse.
3. A share link with a hostile diagram: no script, no remote request.
4. Print straight after a first load: `print` must wait for the diagrams.
5. Offline PWA: the lazy diagram chunks must be in the service worker's asset list.

---

### Task 1: The renderer

**Files:**
- Modify: `package.json`, `package-lock.json`
- Create: `src/mermaid.js`
- Test: `src/mermaid.test.js`

**Interfaces:**
- Produces: `hasDiagrams(root: ParentNode): boolean` and `renderDiagrams(root: ParentNode, render = peleRender): Promise<void>`. `render(text)` returns `{svg}` or throws.

- [ ] **Step 1:** Run `npm install pele@^1.13.0`.
- [ ] **Step 2: Write the failing tests** in `src/mermaid.test.js`, with `// @vitest-environment happy-dom` and a fake `render`:
  - `replaces a mermaid fence with its svg and keeps data-line`
  - `leaves other code blocks alone`
  - `shows the source and the error as text for a diagram that fails` (message `<b>x</b>` must appear as literal text, and `querySelector('b')` is null)
  - `does not call render twice for the same source` (cache)
  - `passes links false and images false` for the default render, by a spy on the lazy import
  - `a hostile label produces no script element`, with the real pele
- [ ] **Step 3:** Run `npx vitest run src/mermaid.test.js`. Expected: FAIL, the module does not exist.
- [ ] **Step 4: Implement `src/mermaid.js`.** The default render does `const { renderAsync } = await import('pele/lazy')`. The cache is a `Map` from source to `{svg}` or `{error}`, bounded at 64 entries. On success, set `pre.classList.add('mermaid')` and `pre.innerHTML = svg`. On failure, add the class `mermaid-error`, then append a `code` with the source and a `p` with the message, both through `textContent`.
- [ ] **Step 5:** Run the tests and `npm run typecheck`. Expected: PASS.
- [ ] **Step 6:** Commit: `web: render mermaid fences with Pele`.

### Task 2: Preview and theme

**Files:**
- Modify: `src/editor.js` (`updatePreview`), `src/style.css`
- Test: `src/mermaid.test.js`

**Interfaces:**
- Consumes: `renderDiagrams`, `hasDiagrams`.

- [ ] **Step 1:** In `updatePreview`, after `preview.innerHTML = ...`, call `renderDiagrams(preview)` if `hasDiagrams(preview)`. Keep a generation number and do nothing if a newer render has started. After it resolves, call `invalidatePreviewBlocks()`, then `syncPreviewToEditor()` in Split, because the block heights changed.
- [ ] **Step 2:** In `src/style.css`, on `#preview .pele`, map `--pele-bg` to `transparent`, `--pele-fg` to `var(--fg)`, `--pele-muted` to `var(--fg-dim)`, `--pele-line` to `var(--fg-dim)`, `--pele-surface` to `var(--bg-elev)`, `--pele-surface-alt` to `var(--bg-deep)`, `--pele-border` to `var(--border)`, `--pele-accent` to `var(--accent)`. Style `pre.mermaid` with no box, and `pre.mermaid-error` as a code block with the message in `--fg-dim`.
- [ ] **Step 3:** Add a test: the built `sw.js` asset list contains a chunk with `flowchart` in its name, or extend `src/sw.test.js` if it reads the build.
- [ ] **Step 4:** Run `npm run build && npm run preview`. In a browser, check a flowchart and a sequence diagram in Pequod dark and light, an invalid diagram, editing a diagram in Split, and switching the palette with no re-render.
- [ ] **Step 5:** Commit: `web: diagrams in the preview take the palette`.

### Task 3: Print and export

**Files:**
- Modify: `src/editor.js` (`printPreview`, `exportHtml`)
- Modify: `CHANGELOG.md`, `CLAUDE.md`, `PRODUCT.md`
- Test: `src/mermaid.test.js`

**Interfaces:**
- Produces: `renderDiagramsInHtml(html: string, render?): Promise<string>`, which runs `renderDiagrams` on a `template` element and returns its `innerHTML`.

- [ ] **Step 1: Write the failing test** `renderDiagramsInHtml returns the html with svg in place`.
- [ ] **Step 2:** Implement it. In `printPreview`, await `renderDiagrams(preview)` before `window.print()`. In `exportHtml`, pass `rendered` through `renderDiagramsInHtml`, and add a `.pele` rule to the file's style block that sets the `--pele-*` variables from `p`, because the file has no palette variables.
- [ ] **Step 3:** Run `npm test`, `npm run typecheck` and `npm run build`. Expected: all pass. Print one document with a diagram and open one exported file.
- [ ] **Step 4:** Add the changelog entry, a line for `src/mermaid.js` in CLAUDE.md, and in PRODUCT.md the diagrams in Features and the known gap in the native app.
- [ ] **Step 5:** Commit: `web: diagrams in print and HTML export`.
