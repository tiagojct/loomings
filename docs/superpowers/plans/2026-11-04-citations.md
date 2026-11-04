# Citations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recognise `[@key]` citations from a `.bib` file, format them with a CSL style, and show a reference list, in the web and native apps.

**Architecture:** All rules are in `src/citations/` (pure JavaScript). The web runs them in a worker, and the native app runs one bundle in JavaScriptCore on its own queue. The frontmatter is the only store of the choice. The result is a `CitationReport`, which both apps apply to the rendered output.

**Tech Stack:** citeproc, @citation-js/core, @citation-js/plugin-bibtex, @codemirror/autocomplete, JavaScriptCore.

**Spec:** `docs/superpowers/specs/2026-11-04-citations-and-diagrams.md`, section Citations.

## Global Constraints

- Keys and syntax are Pandoc's. No invented syntax.
- A document without `bibliography:` renders byte for byte as today. All HTML fixtures stay valid.
- No network. `sync-fetch-undici` is aliased to a stub that throws, on both surfaces.
- The code loads only when a document has `bibliography:` or the References tab opens.
- Citation work never runs on the edit path and never joins the teaching report.
- Citeproc output is untrusted: only `i`, `b`, `sup`, `sub`, `span`, and `a` with a `SAFE_URL` href reach the DOM.
- No Claude author, co-author or session lines in commits. Follow CLAUDE.md for STE and European Portuguese.

## Review Focus

1. One broken entry in a 200-entry `.bib`: the other 199 work, and a note gives the entry's line.
2. A dependent or broken `.csl` file: a clear message names the parent style, with no `[NO_PRINTED_FORM]`.
3. Typing during a slow render: the keystroke is not delayed, and a stale result is dropped.
4. A file in Latin-1 or with a BOM, or CRLF: accents survive or the note says why not.
5. `a@b.pt`, `@` in code, an accented key and a key with a colon: only real citations match.

---

## Part A: Core

### Task 1: Frontmatter keys

**Files:**
- Create: `src/citations/frontmatter.js`
- Test: `src/citations/frontmatter.test.js`

**Interfaces:**
- Produces: `readCitationMeta(source): {bibliography: string[], csl: string|null, lang: string|null, title: string|null, references: object[]}` and `setCitationMeta(source, key: 'bibliography'|'csl', value: string|null): string`.
- Consumes: `splitLines`, `frontmatterLines` from `src/teaching/parse.js`.

- [ ] **Step 1: Write the failing tests:** one name, flow list `[a.bib, b.bib]`, block list, quotes, no frontmatter, a `---` after line 50, a one-line JSON `references: [...]` (kept as objects), a malformed `references:` line (empty array, no throw). `setCitationMeta` replaces a key, adds a key, removes a key at `null`, creates a frontmatter when none exists, keeps CRLF, keeps `check:` lines.
- [ ] **Step 2:** Run `npx vitest run src/citations`. Expected: FAIL.
- [ ] **Step 3:** Implement line-based edits, with no YAML library. Follow `directives.js`.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Commit: `citations: read and write the frontmatter keys`.

### Task 2: Scanner

**Files:**
- Create: `src/citations/scan.js`
- Test: `src/citations/scan.test.js`

**Interfaces:**
- Produces: `scanCitations(source): Citation[]`, with `Citation = {from, to, bare: boolean, items: CiteItem[]}` and `CiteItem = {key, prefix, suffix, locator, label, suppressAuthor}`. Offsets are UTF-16.
- Consumes: `parseSource` from `src/teaching/parse.js`, for code and frontmatter ranges.

- [ ] **Step 1: Write the failing tests:** `[@key]`, `[@a; @b]`, `[see @key, p. 3]` (prefix `see `, locator `3`, label `page`), `[-@key]`, bare `@key.`, keys `smith:2020` and `ciência2020`, `a@b.pt` not matched, `\@key` not matched, code span and fence not matched, frontmatter not matched, `[text](url)` not matched, an offset after an emoji.
- [ ] **Step 2:** Run them. Expected: FAIL.
- [ ] **Step 3:** Implement. Key pattern: start with a letter, digit or `_`, then those or internal `:.#$%&-+?<>~/`, with no trailing punctuation. Labels: `p.`, `pp.`, `chap.`, `sec.`, `vol.`, `fig.`.
- [ ] **Step 4:** Run them. Expected: PASS.
- [ ] **Step 5:** Commit: `citations: find citations in the source`.

### Task 3: Bibliography parser

**Files:**
- Modify: `package.json`, `package-lock.json`, `vite.config.js`, `vitest.config.js`
- Create: `src/citations/bib.js`, `src/citations/stub-fetch.js`
- Test: `src/citations/bib.test.js`

**Interfaces:**
- Produces: `parseBibliography(text): {items: CslItem[], notes: {line, key?, message}[]}`.

- [ ] **Step 1:** Run `npm install citeproc @citation-js/core @citation-js/plugin-bibtex`. Alias `sync-fetch-undici` to the stub in both config files.
- [ ] **Step 2: Write the failing tests:** `J{\'a}come` gives `Jácome`, `@string` resolves, BOM and CRLF, empty text, `@comment`. An unbalanced entry among three leaves the other two, with a note on its line. A duplicate key keeps the first entry, with a note. A bad entry never throws.
- [ ] **Step 3:** Run them. Expected: FAIL.
- [ ] **Step 4:** Implement. Split the text into top-level `@` blocks with a brace counter, keep the line of each, collect `@string` blocks first, and parse each entry alone with `@biblatex/text`, prefixed by the strings. If a counted block never closes, resume at the next line that starts with `@`.
- [ ] **Step 5:** Run them, and time the 191-entry file. Expected: PASS, and parse below 100 ms in Node.
- [ ] **Step 6:** Commit: `citations: parse a bib file entry by entry`.

### Task 4: Engine and styles

**Files:**
- Create: `src/citations/engine.js`, `src/citations/style.js`, `src/citations/assets.js`
- Create: `src/citations/styles/*.csl`, `src/citations/locales/*.xml`, `src/citations/LICENSE-CSL.md`
- Test: `src/citations/engine.test.js`

**Interfaces:**
- Produces: `checkStyle(xml): {ok: true, title} | {ok: false, reason: 'invalid'|'dependent', parent?: string}`.
- Produces: `createEngine({styleXml, localeXml, lang, items}): {render(citations): {texts: string[], bibliography: string[]}}`.
- Produces (web only): `loadBundledStyle(id)`, `loadLocale(lang)`, through `import.meta.glob` with `?raw`, and `BUNDLED_STYLES: {id, title}[]`.

- [ ] **Step 1:** Copy the five styles and four locales from the CSL repositories. `nlm-citation-sequence.csl` becomes `vancouver.csl`. Do not edit them.
- [ ] **Step 2: Write the failing tests:** APA gives `(Jácome et al., 2020)`. Vancouver gives a number. `[see @a, p. 3]` keeps prefix and locator. `pt-PT` uses Portuguese terms. An unknown key is left out and the others render. Only unknown keys give `''`. Two calls to `render` give equal output. `checkStyle` reports `dependent` with the parent, and `invalid` for text that is not XML.
- [ ] **Step 3:** Run them. Expected: FAIL.
- [ ] **Step 4:** Implement. Build the engine once and reuse it. Call `updateItems` with the used keys, then `processCitationCluster` with a fresh citation list on each render. Bare citations use `author-only` plus `suppress-author`.
- [ ] **Step 5:** Run them. Expected: PASS.
- [ ] **Step 6:** Commit: `citations: format with CSL`.

### Task 5: Report and worker

**Files:**
- Create: `src/citations/session.js`, `src/citations/output.js`, `src/citations/worker.js`, `src/citations/client.js`
- Test: `src/citations/session.test.js`, `src/citations/output.test.js`

**Interfaces:**
- Produces: `createSession(): {setSources({bibs: {name, text}[], styleXml, localeXml, lang}), analyse(source): CitationReport, shareSource(source): string}`. `analyse` adds the source's `references:` entries to the library, and a `.bib` entry with the same key wins. An entry in `references:` needs a string `id` and an object shape, or it is dropped with a note.
- Produces: `CitationReport = {citations: {from, to, html, markdown, missing: string[]}[], bibliography: string[], bibliographyMarkdown: string, library: {key, authors, year, title, cited: boolean}[], notes: {from, to, message}[], markdownSource: string}`.
- Produces: `applyCitations(source, report): {text, fill(html): string}` for the web. Each citation becomes a private-use marker with the same line count, and `fill` swaps the markers for `<span class="cite">` after the render.
- Produces: `cleanCitationHtml(html): string`, the allowlist of the Global Constraints, with no DOM.
- Produces: `createCitationClient()` with `update(source)` and `onReport`. It keeps the latest id and drops older answers, as the teaching worker does.

- [ ] **Step 1: Write the failing tests:** a report for two citations and one unknown key. A note for an unknown key gives its range. `markdownSource` has the same line count as the source up to its last line. `javascript:` in a bib `url` gives no `a` element. `<script>` in a title stays text. `<i>` becomes `*`. Library entries carry `cited`.
- [ ] **Step 2:** Run them. Expected: FAIL.
- [ ] **Step 3:** Implement. The session rebuilds the engine only when the style, locale or language changes.
- [ ] **Step 4:** Run them, and `npm run typecheck`. Expected: PASS.
- [ ] **Step 5:** Commit: `citations: the report, off the main thread`.

## Part B: Web

### Task 6: Files in the browser

**Files:**
- Modify: `src/browser.js` (key `citation-file:<name>` in the existing store, so no DB version change; `initDragDrop`)
- Create: `src/citations/library.js`
- Test: `src/browser.test.js`, `src/citations/library.test.js`

**Interfaces:**
- Produces: `listCitationFiles()`, `saveCitationFile({name, kind, text, handle?})`, `deleteCitationFile(name)`, `pickCitationFile()` in `browser.js`.
- Produces: `resolveSources(meta, files, assets): {bibs, styleXml, localeXml, lang, missing: string[], styleError?: string}`.

- [ ] **Step 1: Write the failing tests:** save, list and delete with fake-indexeddb. Match by base name, ignoring case. `csl: apa` finds the bundled style, and a stored `apa.csl` wins. A missing name is in `missing`. A dependent style sets `styleError` with the parent's name. A failed write is contained, as `session.js` does.
- [ ] **Step 2:** Run them. Expected: FAIL.
- [ ] **Step 3:** Implement. `initDragDrop` takes `.bib` and `.csl` to a new callback, and documents keep their path. Decode with `TextDecoder('utf-8', {fatal: true})`, then try `windows-1252` with a note. Re-read a stored handle on window focus, without asking for permission on focus.
- [ ] **Step 4:** Run them. Expected: PASS.
- [ ] **Step 5:** Commit: `web: keep bib and csl files in the browser`.

### Task 7: Preview and exports

**Files:**
- Modify: `src/editor.js` (`updatePreview`, `printPreview`, `exportHtml`), `src/style.css`

**Interfaces:**
- Consumes: `createCitationClient`, `applyCitations`, `readCitationMeta`, `resolveSources`.

- [ ] **Step 1:** In `updatePreview`, read the meta. With `bibliography:`, render `applyCitations(...).text`, call `fill` on the HTML, and append `<section class="references">`. Until the first report arrives, keep the literal text.
- [ ] **Step 2:** Add a test in `src/markdown.test.js`: a document without `bibliography:` gives today's output.
- [ ] **Step 3:** `printPreview` and `exportHtml` await the current report. Add the styles for `.cite` and `.references`, with a hanging indent for numbered styles.
- [ ] **Step 4:** Run `npm test` and `npm run build`. In a browser, check the 191-entry file with Vancouver and APA in `pt-PT`, and type at speed in a long document. Expected: no delay at the caret.
- [ ] **Step 5:** Commit: `web: citations and references in the preview, print and export`.

### Task 8: Editor

**Files:**
- Modify: `package.json`, `src/editor.js`
- Create: `src/citations/editor.js`
- Test: `src/citations/editor.test.js`

**Interfaces:**
- Produces: `citationExtensions(getReport): Extension[]`, with a mark decoration on citation ranges for visible lines and `autocompletion` on `@`.
- Produces: `citationCompletions(context, library)`, pure and tested, which matches key, author and title, accents ignored.

- [ ] **Step 1:** Run `npm install @codemirror/autocomplete`.
- [ ] **Step 2: Write the failing tests** for `citationCompletions`: `@jac` finds `jacome2020`, `@jacome asthma` matches the title, nothing inside a code span, nothing in an email.
- [ ] **Step 3:** Implement. Add `report.notes` to the notes list that the checker fills, in the same format. A note for a missing file has the action "Add references.bib". Check that the learner's checker adds no note on `[@key]`.
- [ ] **Step 4:** Run the tests and `npm run typecheck`. Expected: PASS.
- [ ] **Step 5:** Commit: `web: citation colours, notes and completion`.

### Task 9: References tab and selectors

**Files:**
- Modify: `src/index.html`, `src/editor.js`, `src/style.css`
- Create: `src/citations/panel.js`
- Test: `src/citations/panel.test.js`

**Interfaces:**
- Produces: `renderLibrary(root, report, filter)`, `filterLibrary(library, query)`.
- Consumes: `setCitationMeta`, `pickCitationFile`, `BUNDLED_STYLES`.

- [ ] **Step 1: Write the failing tests:** the filter ignores accents, cited entries are marked, missing keys come first, every label is escaped.
- [ ] **Step 2:** Implement. The Split right column gets tabs Preview and References with `role="tablist"`, and the tab stays per session. A toolbar References menu through `attachMenu` has Add File…, the bibliography list and the style list. A choice changes the frontmatter with one `view.dispatch`, so Undo reverts it. A click on an entry inserts `[@key]` at the caret. On a narrow screen, References replaces Preview. Say in the menu that files stay in this browser.
- [ ] **Step 3:** Run `npm test`, `npm run typecheck` and `npm run build`. Check the keyboard path and the projector.
- [ ] **Step 4:** Add About attribution for citeproc and the CSL files, the changelog entry and PRODUCT.md Features.
- [ ] **Step 5:** Commit: `web: the references tab and the style and bibliography choices`.

## Part C: Native

### Task 10: The bundle in JavaScriptCore

**Files:**
- Create: `vite.citations.config.js`, `src/citations/native-entry.js`
- Modify: `scripts/export-native-resources.mjs`, `macos/Package.swift`
- Create: `macos/Resources/Citations/` (generated), `macos/Sources/LoomingsCitations/CitationEngine.swift`, `macos/Sources/LoomingsCitations/CitationReport.swift`
- Create: `macos/scripts/render-citation-fixtures.mjs`
- Test: `macos/Tests/LoomingsCitationsTests/`, with Fixtures

**Interfaces:**
- Produces (JS): global `LoomingsCitations` with `setSources(json)`, `analyse(source): string`, `readMeta(source): string`, `setMeta(source, key, value): string`, `checkStyle(xml): string`.
- Produces (Swift): `final class CitationEngine: @unchecked Sendable` with `init(resources: URL) throws`, `setSources(_:)`, `analyse(_ source: String) -> CitationReport`, all on one private serial queue. `struct CitationReport: Decodable, Sendable`, field for field as in Task 5.

- [ ] **Step 1:** Add the iife build, with a banner that defines `process`, `TextEncoder` and `TextDecoder` for JavaScriptCore. Export the bundle, styles and locales from the export script. Check that `build-app.sh` copies them.
- [ ] **Step 2: Write the failing Swift test:** decode a fixture made by the web code, run the same input through `CitationEngine`, and expect an equal report. A JavaScript exception gives an empty report with a note, and no crash.
- [ ] **Step 3:** Run `swift test --package-path macos`. Expected: FAIL.
- [ ] **Step 4:** Implement. Load the bundle lazily, on the first use.
- [ ] **Step 5:** Run the tests. Expected: PASS. Record the startup with and without a bibliography in `macos/ACCEPTANCE.md`.
- [ ] **Step 6:** Commit: `macos: run the citation code in JavaScriptCore`.

### Task 11: Controller and preview

**Files:**
- Create: `macos/Sources/LoomingsApp/CitationController.swift`
- Modify: `macos/Sources/LoomingsApp/EditorWindowController.swift`, `macos/Sources/LoomingsApp/SelfTest.swift`

**Interfaces:**
- Produces: `CitationController` on the main actor, with `update(source:documentURL:)` and `onReport`. It debounces by 400 ms and keeps a generation token.
- Consumes: `CitationEngine`, `FileChangeDetector`.

- [ ] **Step 1: Write the failing self-test checks:** a document with `bibliography:` next to it shows a formatted citation in the preview. Without the key, the source reaches the renderer unchanged. A stale report is dropped. Insert p95 stays the same with a slow engine.
- [ ] **Step 2:** Implement. Resolve names against the document's folder, and read files through `TextFileCodec`. The preview and HTML export render `report.markdownSource` in place of the source. Check files again on activation, and do not join `companionAnalysis`.
- [ ] **Step 3:** Run `./macos/scripts/build-app.sh` and `--self-test`. Expected: SELFTEST PASS. Take a `--snapshot` for design review.
- [ ] **Step 4:** Commit: `macos: citations in the preview and export`.

### Task 12: Editor marks and completion

**Files:**
- Modify: `macos/Sources/LoomingsEditor/EditorController.swift`, `macos/Sources/LoomingsEditor/EditorTextView.swift`, `macos/Sources/LoomingsApp/EditorWindowController.swift`
- Test: `macos/Tests/LoomingsEditorTests/EditorControllerTests.swift`

**Interfaces:**
- Produces: `EditorController.citationRanges: [NSRange]`, `citationKeys: [CitationCompletion]`, and a `citations` decoration owner on `EditorTextView`.

- [ ] **Step 1: Write the failing tests:** `completions(forPartialWordRange:)` returns keys after `@`, nothing in an email. Unknown-key ranges become squiggles. Marks never advance the revision.
- [ ] **Step 2:** Implement with `EditorDecoration`, because rendering attributes cannot change laid-out text. Use the native `complete:` popup, opened on `@`.
- [ ] **Step 3:** Run the tests. Expected: PASS.
- [ ] **Step 4:** Commit: `macos: citation marks and completion`.

### Task 13: Menu and References column

**Files:**
- Create: `macos/Sources/LoomingsApp/ReferencesView.swift`
- Modify: `macos/Sources/LoomingsApp/AppDelegate.swift`, `macos/Sources/LoomingsApp/EditorWindowController.swift`, `macos/Sources/LoomingsApp/SelfTest.swift`
- Modify: `CHANGELOG.md`, `CLAUDE.md`, `PRODUCT.md`, `macos/ACCEPTANCE.md`

**Interfaces:**
- Consumes: `setMeta` through `CitationEngine`, `CitationReport.library`.

- [ ] **Step 1:** Add the References menu: Choose Bibliography… and Citation Style with the bundled styles and Choose File… (`NSOpenPanel`). A choice applies `setMeta` as one undoable replacement of the frontmatter range. A dependent style gives a sheet that names the parent.
- [ ] **Step 2:** Add Show References. The Split right column switches between the preview and `ReferencesView`: a filter field and a table of the library, marked cited or not. Return or a double click inserts `[@key]`.
- [ ] **Step 3:** Add self-test checks for the undoable edit and the insertion. Check VoiceOver labels.
- [ ] **Step 4:** Run `swift test --package-path macos`, the self-test, `npm test` and `npm run typecheck`. Expected: all pass.
- [ ] **Step 5:** Update the docs, with an About credit. Record the parity state in `macos/ACCEPTANCE.md`.
- [ ] **Step 6:** Commit: `macos: the references menu and column`.

### Task 14: Share links carry the cited entries

**Files:**
- Modify: `src/citations/session.js`, `src/editor.js` (`copyShareLink`, `printPreview`, the QR dialog at the `shareUrl` call near line 1651), `src/citations/native-entry.js`
- Modify: `macos/Sources/LoomingsCitations/CitationEngine.swift`, `macos/Sources/LoomingsApp/EditorWindowController.swift` (both `ShareLink.url` calls), `macos/Sources/LoomingsApp/Handout.swift`
- Test: `src/citations/session.test.js`, `macos/Tests/LoomingsCitationsTests/`, `macos/Sources/LoomingsApp/SelfTest.swift`

**Interfaces:**
- Consumes: `setCitationMeta`, `createSession`.
- Produces: `shareSource(source): string` (Task 5 declares it; this task fills it). `CitationEngine.shareSource(_ source: String) -> String`.

- [ ] **Step 1: Write the failing tests:** only cited entries are in the line. The line is one line, and `JSON.parse` of its value equals the entries. A document with no citations, or with no `bibliography:`, comes back unchanged. An existing `references:` line is replaced, not repeated. A round trip through `shareUrl` and `decodeDoc`, then a session with no `.bib`, gives the same citation texts as the writer's session. The line count of the body does not matter, but the writer's document is unchanged.
- [ ] **Step 2:** Run them. Expected: FAIL.
- [ ] **Step 3:** Implement. Web: every `shareUrl` call passes `await citationClient.shareSource(text)` when the document has `bibliography:`, and a failed call falls back to the plain text. A worker that is not ready waits for its sources. Native: `shareSource` runs on the engine's queue. It parses and scans but does not format, so it is fast enough to wait for at a menu command.
- [ ] **Step 4:** Add the note for an uploaded style that cannot travel: the status text after Copy Share Link says the receiver gets the default style.
- [ ] **Step 5:** Run `npm test`, `npm run typecheck`, `swift test --package-path macos` and the self-test. Expected: all pass. In a browser, open a copied link in a private window with no stored files and check the citations and the list.
- [ ] **Step 6:** Update the changelog and CLAUDE.md. Commit: `web, macos: share links carry the cited entries`.
