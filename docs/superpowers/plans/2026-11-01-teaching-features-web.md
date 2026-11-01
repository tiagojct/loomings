# Teaching Features (web port) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring features 1, 2, 3, 4, 6, 8 and 9 of the spec to the web app, matching the native app through the shared fixtures.

**Architecture:** Pure rule modules under `src/teaching/` (no DOM), each tested with Vitest against the JSON fixtures in `macos/Tests/LoomingsTeachingTests/Fixtures/`, which are the contract with the native app. `src/editor.js` wires them into CodeMirror (decorations, DOM handlers) and the existing status bar, menus and preview. The checker and checks run on markdown-it tokens (the preview's parser) plus line scans; the glossary reads the editor's lezer syntax tree.

**Tech Stack:** Vite 8, CodeMirror 6 (`@codemirror/view` decorations and `domEventHandlers`, `@codemirror/lang-markdown` syntax tree), markdown-it 14, Vitest 5, happy-dom, `tsc` typecheck.

**Spec:** `docs/superpowers/specs/2026-11-01-teaching-features.md` (features 1, 2, 3, 4, 6, 8, 9; 5, 7 and 10 stay native).

## Global Constraints

- No new runtime or dev dependencies (the machine is offline; the QR encoder is written here).
- CSP stays as in `nginx.conf`: self-only scripts and styles; `data:` images are allowed.
- Colours only from `src/palettes.js` through the CSS variables `editor.js` writes; no new hex values.
- UI copy in English, British spelling; the same wording as the native app wherever both show the same thing.
- Rule ids, messages and check labels are identical to the native ones: the fixtures pin them.
- `npm test`, `npm run typecheck` and `npm run build` pass after every task.
- Projector mode never writes `localStorage`.
- Each task is one commit, staging only the files it lists. No Claude author, co-author or session lines.
- Version: bump `package.json` to 2.4.0 in the last task only.

## Review Focus

- markdown-it and cmark disagree on an edge case the fixtures do not cover (for example a setext heading inside a list): the web gives a note the native app does not, or the reverse. Expected: the same notes for the bundled lessons and the fixture cases; add a fixture for any disagreement found.
- A 1 MB document: typing stays responsive because the checker runs after the existing debounce and decorations cover only `view.visibleRanges`.
- Touch and keyboard users: option-click does not exist on a phone; "Explain marker at cursor" (Mod-Alt-/) gives the same explanation.
- Printing in Safari, which lacks `@page` margin boxes: the handout prints without page numbers but otherwise intact.
- A lesson opened from `?lesson=` and then edited at its last line: checks fail closed, as native.

---

### Task 1: Paired lines in Split view (feature 1)

**Files:**
- Modify: `src/markdown.js` (stamp `data-line-end` next to `data-line`, from `token.map[1]`)
- Modify: `src/editor.js` (pointer handlers, a line-decoration field, preview highlight class)
- Modify: `src/style.css` (`.paired` on preview blocks, `.cm-paired-line` in the editor, both from `--selection` at 45 %)
- Test: `src/markdown.test.js`, new `src/pairing.test.js`

**Interfaces:**
- Produces: `blockForLine(blocks: {line:number,end:number}[], line: number): number` in new `src/pairing.js` (index or -1; a blank line between blocks gives -1).

- [ ] Write tests: `data-line-end` is stamped on block tokens; `blockForLine` finds a table from a middle row and returns -1 for a blank line.
- [ ] Run `npm test -- pairing markdown`; expect failures.
- [ ] Implement; in Split mode only, `mousemove` over the editor (`view.posAtCoords`) lights the preview block, `mouseover` on a preview block adds `.cm-paired-line` to its source lines; leaving or changing mode clears both.
- [ ] Run tests, typecheck, build; commit `web: paired lines in Split view`.

### Task 2: Learner's checker (feature 2)

**Files:**
- Create: `src/teaching/lint.js`, `src/teaching/lint.test.js`
- Modify: `src/editor.js` (decorations, status-bar notes button, notes popover via `openModal`-style popover in `src/menu.js` conventions), `src/index.html`, `src/style.css`

**Interfaces:**
- Produces: `lint(source: string): {rule, from, to, message, fix?: {from, to, insert, title}}[]` sorted by `from`, UTF-16 offsets.

- [ ] Test: load `macos/Tests/LoomingsTeachingTests/Fixtures/lint-cases.json` with `fs`; for every case the rule list and the text after applying all fixes (last first) equal the fixture. Also: every bundled lesson, `examples/loomings.md` and the cheatsheet give no notes; `"😀 x\r\n#Title\r\n"` fixes to `"😀 x\r\n# Title\r\n"`.
- [ ] Run; expect failure (module missing).
- [ ] Implement: markdown-it tokens give paragraph line spans (`map`), headings (setext when the line does not start with `#`), fences reaching the end, images (alt from `children`), leftover `**`/`__` in text; line scans for `heading-space`, `ordered-list-interrupt`, `link-space`, `table-separator`; frontmatter and code never checked; escaped marks ignored; fixes keep the document's line ending.
- [ ] UI: wavy underline marks (`Decoration.mark`, class `cm-note`, colour `--accent`) built only for `view.visibleRanges`; they rest while typing (cleared on change, rebuilt after the existing preview debounce); status bar `N notes` button opens a list with Fix and Go to line; a fix is one CodeMirror transaction (undoable) and closes the list.
- [ ] Tests, typecheck, build; commit `web: learner's Markdown checker`.

### Task 3: Explain this marker (feature 3)

**Files:**
- Create: `src/teaching/glossary.js`, `src/teaching/glossary.test.js`
- Create: `macos/Tests/LoomingsTeachingTests/Fixtures/glossary-cases.json`; Modify: `macos/Tests/LoomingsTeachingTests/MarkerGlossaryTests.swift` (read the same fixture)
- Modify: `src/editor.js`

**Interfaces:**
- Produces: `explain(kind: string, marker: string): {title, body, lesson?} | null` with the native kinds (`headingMarker`, `emphasisMarker`, `strongMarker`, `strikethroughMarker`, `inlineCodeMarker`, `fencedCodeDelimiter`, `blockQuoteMarker`, `listMarker`, `linkPunctuation`, `imagePunctuation`, `thematicBreak`, `rawHTML`, `frontmatter`); `markerAt(state, pos): {kind, from, to} | null` mapping lezer nodes (`HeaderMark`, `EmphasisMark` by run length, `CodeMark`, `LinkMark`, `ListMark`, `TaskMarker`, `QuoteMark`, `HorizontalRule`, `HTMLTag`/`HTMLBlock`) to those kinds.
- Fixture: an array of `{kind, marker, title, lesson}`, one or more per kind; titles and bodies must equal the Swift glossary.

- [ ] Write the fixture from the Swift glossary; add the Swift test that reads it; write the JS test; run both; the JS one fails.
- [ ] Implement; Alt-click in the editor and Mod-Alt-/ at the cursor show a popover with the title, body and "Open the lesson" (navigates with `?lesson=`); a note under the click wins over the marker.
- [ ] `npm test`, `swift test --package-path macos --disable-automatic-resolution`, typecheck, build; commit `web: explain a marker; shared glossary fixture`.

### Task 4: Exercises that check themselves (feature 4)

**Files:**
- Create: `src/teaching/directives.js`, `src/teaching/exercises.js`, tests for both
- Modify: `src/editor.js` (status item `Exercise 2 of 4` / `Exercise done`, checklist popover; attach `lessons/checks.json` when a lesson opens)

**Interfaces:**
- Produces: `readDirectives(source): {key, value, line}[]`; `parseCheck(directive): {ok: true, check} | {ok: false, note: {line, message}}`; `parseLimit(directive)` likewise; `evaluate(source, attached?: {checks, after}): {results: {label, passed, detail}[], notes}`.

- [ ] Tests: `check-cases.json` (all cases), the malformed directives of the native `DirectivesTests`, and for every lesson in `lessons/checks.json`: untouched passes nothing, an answer passes everything, deleting the lesson's last character passes nothing (reuse the native answers).
- [ ] Run; expect failure. Implement the census on markdown-it tokens; reference links found by scanning the source for `[text][id]` whose id is in `env.references`; scope for attached checks exactly as native (prefix, last line, common prefix; never the whole document).
- [ ] UI; tests, typecheck, build; commit `web: exercises that check themselves`.

### Task 5: Section word limits (feature 9)

**Files:**
- Create: `src/teaching/sections.js` and test; Modify: `src/editor.js` (status item; counts in the heading palette)

**Interfaces:**
- Consumes: `parseLimit` (Task 4), `extractHeadings` (existing), `countWords` (`src/stats.js`).
- Produces: `sections(source, headings, limits, {onlyLimited}): {heading, from, to, words, limit}[]`.

- [ ] Tests mirroring native `SectionStatisticsTests` (nesting, own heading not counted, case-insensitive match, only limited sections); run; fail; implement.
- [ ] Status item keeps its last value between edits (it only changes when a fresh result arrives); the palette shows `Title — 180/200`.
- [ ] Tests, typecheck, build; commit `web: section word limits`.

### Task 6: Projector mode (feature 6)

**Files:**
- Modify: `src/editor.js`, `src/index.html` (View menu item, caption element), `src/style.css` (`body.projector`)

**Interfaces:**
- Produces: `toggleProjector()`; Ctrl-Mod-P; a caption naming markup just typed or applied, reusing the native phrases ("Heading 2: ## ", "Bold: **text**").

- [ ] Test (happy-dom): toggling adds `body.projector`, sets the editor font to 28 px and preview to 26 px, hides the status bar, and writes nothing to `localStorage`; a typed `## ` at a line start yields the caption "Heading 2: ## ".
- [ ] Implement; the caption fades after 1.6 s unless `prefers-reduced-motion`, and is an `aria-live="polite"` region.
- [ ] Tests, typecheck, build; commit `web: classroom projector mode`.

### Task 7: Handout print and QR code (feature 8)

**Files:**
- Create: `src/qr.js` (byte mode, error correction L, versions 1–40, standard mask choice), `src/qr.test.js`
- Create: `scripts/render-qr-fixtures.mjs` writing `macos/Tests/LoomingsShareTests/Fixtures/qr-matrices.json`; Modify: `macos/Tests/LoomingsShareTests/ShareQRCodeTests.swift` (render each matrix and decode it with `CIDetector`)
- Modify: `src/editor.js` (print adds the QR block; share menu "Show QR code"), `src/style.css` (`@media print`: `@page { size: A4 }` or Letter by `navigator.language`, `@page { @bottom-center { content: counter(page) " of " counter(pages) } }`)

**Interfaces:**
- Produces: `qrMatrix(text: string): boolean[][] | null` (null above 2,900 UTF-8 bytes); `qrSvg(text, modulePx): string | null`.

- [ ] Tests: version selection for 10, 100, 1,000 and 2,900 bytes; null above the limit; format and version bits for known cases; matrices have the finder patterns. Swift: every matrix in the fixture decodes back to its text.
- [ ] Run; fail; implement.
- [ ] Print: the preview is printed with the light colours of the family, a QR block at the end ("Scan to open this document in Loomings." or the too-long sentence), page numbers where the browser supports margin boxes.
- [ ] Tests (JS and Swift), typecheck, build; commit `web: handout print with a QR code`.

### Task 8: Release notes and version

**Files:** `package.json` (2.4.0), the changelog in `docs/` if present, `CLAUDE.md` (teaching modules, shared fixtures)

- [ ] `npm test`, typecheck, build; check the service worker precaches the new chunks (`src/sw.test.js`); commit `web: 2.4.0 teaching features`.

---

Deploying 2.4.0 to loomings.tiagojacinto.eu is a separate step that needs the owner's go-ahead.
