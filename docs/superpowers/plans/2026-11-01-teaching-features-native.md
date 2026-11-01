# Teaching Features (native) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the ten teaching features of the spec in the native macOS app.

**Architecture:** A new pure SwiftPM target `LoomingsTeaching` (depends on `LoomingsMarkdown`, Foundation only) holds every rule, parser and algorithm: the checker, frontmatter directives, exercise checks, section limits, the marker glossary, the line diff and the history log. `LoomingsApp` holds the views (popovers, status-bar items, compare and replay windows, overlay, handout printing, sharing). Shared JSON fixtures under `macos/Tests/LoomingsTeachingTests/Fixtures/` are the contract the web port will test against.

**Tech Stack:** Swift 6.1 tools, Swift language mode 5, AppKit, TextKit 2 (editor), TextKit 1 (preview), cmark-gfm through `MarkdownTree`, Swift Testing, CoreImage (QR), NSSharingService (AirDrop).

**Spec:** `docs/superpowers/specs/2026-11-01-teaching-features.md`

## Global Constraints

- macOS 15+, arm64; `swift-tools-version: 6.0`, `swiftLanguageModes: [.v5]`.
- No new package dependencies; no network requests.
- Colours only from `ResolvedPalette.colors` (system colours when nil).
- UI copy in English with British spelling ("colour", "centre").
- Typing never waits: checker, checks, limits and history run on the editor's background analysis or later, never in `textDidChange`.
- Every source range is UTF-16 and goes through `SourceMap`.
- One commit per task; messages without Claude author, co-author or session lines (workspace rule).
- After each task: `swift test --package-path macos --disable-automatic-resolution` passes, `./macos/scripts/build-app.sh` builds, `macos/dist/Loomings.app/Contents/MacOS/Loomings --self-test` prints `SELFTEST PASS`.

## Review Focus

- A 1 MB document with lint, checks and limits on: insert p95 stays under 2 ms (bench `insert p95`), because the work runs on the background parse. Test in Task 3.
- CRLF files and non-ASCII text before an issue: fix ranges land on the right characters. Test in Task 3 (`fixesWorkAfterEmojiAndCRLF`).
- A recorded document renamed or moved in Finder keeps its history. Test in Task 9 (`historyFollowsRename`).
- A document whose share link exceeds 2,900 bytes: the handout and the QR sheet say the link is too long instead of failing. Test in Task 8 (`qrRefusesLongLinks`).
- Compare of two 20,000-line documents finishes under 1 s and does not allocate an n×m table. Test in Task 10 (`largeDiffIsFast`).
- Malformed directives (`check: banana`, `limit: 200`) are reported as notes and never crash. Test in Task 2 (`malformedDirectives`).
- Projector mode off restores font size, line numbers, status bar and column width exactly. Self-test in Task 7.

---

### Task 1: Paired lines in Split view (feature 1)

**Files:**
- Modify: `macos/Sources/LoomingsApp/PreviewTextView.swift` (pointer tracking, highlight drawing)
- Modify: `macos/Sources/LoomingsEditor/EditorController.swift` (paired range as a rendering attribute)
- Modify: `macos/Sources/LoomingsApp/EditorWindowController.swift` (wire both directions, Split only)
- Modify: `macos/Sources/LoomingsApp/SelfTest.swift`

**Interfaces:**
- Produces: `EditorController.pairedRange: NSRange?` (setter invalidates rendering of old and new range; the validator paints `.backgroundColor` = palette `selectionColor` at 0.45 alpha over it); `EditorController.onPointerLine: ((Int?) -> Void)?` (0-based source line under the pointer, nil when it leaves).
- Produces: `PreviewTextView.highlightedBlockIndex: Int?` (draws a rounded rect, palette `selectionColor` at 0.45, behind that block's glyphs); `PreviewTextView.onPointerBlock: ((PreviewBlock?) -> Void)?`; `PreviewTextView.blockIndex(containingSourceLine: Int) -> Int?`.

- [ ] **Step 1:** Add `blockIndex(containingSourceLine:)` using each block's `sourceLine` and the next block's `sourceLine` as its end. Self-test check: in Split with the lesson `05-tables-rules.md`, `blockIndex(containingSourceLine: 8)` is the first table's index (lines 7 to 11 belong to it).
- [ ] **Step 2:** Editor pointer: a tracking area on the text view; on `mouseMoved` convert the point to a character index (`characterIndexForInsertion(at:)`), then to a line through `analysis.lineStarts`, and call `onPointerLine`. Preview pointer: tracking area; map the point to a glyph, its character to a block through `blockRanges`, call `onPointerBlock`.
- [ ] **Step 3:** In `EditorWindowController`, only when `viewMode == .split`: editor line → `previewTextView.highlightedBlockIndex`; preview block → `editor.pairedRange` = the block's `sourceRange`. Leaving either view clears both. Changing mode clears both.
- [ ] **Step 4:** Self-test checks: setting `pairedRange` does not change `textStorage` contents or `isDocumentEdited` (rendering attribute only); hovering simulated line 8 sets `highlightedBlockIndex` to the table block.
- [ ] **Step 5:** Run the global checks; snapshot Split with a highlight set (add `-LoomingsSnapshotPairLine <n>` to `Snapshot`), confirm the table and its source lines are tinted.
- [ ] **Step 6:** Commit `macos: paired lines in Split view`.

### Task 2: LoomingsTeaching target and frontmatter directives

**Files:**
- Modify: `macos/Package.swift` (target `LoomingsTeaching` → `LoomingsMarkdown`; test target `LoomingsTeachingTests` with `resources: [.copy("Fixtures")]`; `LoomingsApp` depends on it)
- Create: `macos/Sources/LoomingsTeaching/Directives.swift`
- Test: `macos/Tests/LoomingsTeachingTests/DirectivesTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct Directive: Equatable, Sendable { public let key: String; public let value: String; public let line: Int }
  public struct DirectiveNote: Equatable, Sendable { public let line: Int; public let message: String }
  public enum Directives {
      public static func read(_ source: String) -> [Directive]   // only inside the leading frontmatter, keys "check" and "limit"
  }
  public enum ExerciseCheck: Equatable, Sendable {
      case heading(level: Int?, min: Int), bulletList(items: Int), orderedList(items: Int), nestedList, quote,
           codeBlock(language: String?), inlineCode(min: Int), link(min: Int), referenceLink, imageAlt,
           table(rows: Int), emphasis, strong, words(min: Int)
      public static func parse(_ directive: Directive) -> Result<ExerciseCheck, DirectiveNote>
  }
  public struct SectionLimit: Equatable, Sendable { public let heading: String; public let maxWords: Int
      public static func parse(_ directive: Directive) -> Result<SectionLimit, DirectiveNote> }
  ```
  Defaults: `heading` min 1, `bullet-list`/`ordered-list` items 2, `inline-code`/`link` min 1, `table` rows 1, `words` required.

- [ ] **Step 1: Write the failing tests**
  ```swift
  @Test func readsOnlyFrontmatter() {
      let s = "---\ncheck: ordered-list 3\nlimit: Introduction 200\ntitle: x\n---\n\ncheck: heading\n"
      #expect(Directives.read(s).map(\.key) == ["check", "limit"])
  }
  @Test func parsesChecks() {
      #expect(ExerciseCheck.parse(.init(key: "check", value: "ordered-list 3", line: 1)) == .success(.orderedList(items: 3)))
      #expect(ExerciseCheck.parse(.init(key: "check", value: "heading 2", line: 1)) == .success(.heading(level: 2, min: 1)))
      #expect(ExerciseCheck.parse(.init(key: "check", value: "code-block python", line: 1)) == .success(.codeBlock(language: "python")))
  }
  @Test func parsesLimitWithSpacesInTitle() {
      #expect(SectionLimit.parse(.init(key: "limit", value: "Methods and data 350", line: 2)) == .success(.init(heading: "Methods and data", maxWords: 350)))
  }
  @Test func malformedDirectives() {
      guard case .failure(let a) = ExerciseCheck.parse(.init(key: "check", value: "banana", line: 3)) else { Issue.record(); return }
      #expect(a.line == 3 && a.message.contains("banana"))
      guard case .failure = SectionLimit.parse(.init(key: "limit", value: "200", line: 4)) else { Issue.record(); return }
  }
  ```
- [ ] **Step 2:** Run `swift test --package-path macos --filter DirectivesTests`; expect failure (no module).
- [ ] **Step 3:** Implement. Frontmatter bounds from `MarkdownFrontmatter.range(in:)`; a directive line is `^\s*(check|limit)\s*:\s*(.+)$`. `line` is 0-based in the document.
- [ ] **Step 4:** Run the filter again; PASS. Run the global checks.
- [ ] **Step 5:** Commit `macos: LoomingsTeaching target and frontmatter directives`.

### Task 3: Learner's checker (feature 2)

**Files:**
- Create: `macos/Sources/LoomingsTeaching/MarkdownLint.swift`
- Create: `macos/Tests/LoomingsTeachingTests/Fixtures/lint-cases.json`
- Test: `macos/Tests/LoomingsTeachingTests/MarkdownLintTests.swift`
- Modify: `macos/Sources/LoomingsEditor/EditorController.swift` (run lint on the background analysis; wavy underline rendering attribute)
- Modify: `macos/Sources/LoomingsApp/StatusBarView.swift` (clickable "2 notes" item), `EditorWindowController.swift` (issues popover, apply fix)
- Create: `macos/Sources/LoomingsApp/TeachingPopovers.swift` (popover content views shared by Tasks 3, 4, 5)

**Interfaces:**
- Produces:
  ```swift
  public struct LintFix: Equatable, Sendable { public let range: NSRange; public let replacement: String; public let title: String }
  public struct LintIssue: Equatable, Sendable { public let rule: String; public let range: NSRange; public let message: String; public let fix: LintFix? }
  public enum MarkdownLint { public static func lint(_ source: String) -> [LintIssue] }   // sorted by range.location
  ```
  `EditorAnalysis` gains `lintIssues: [LintIssue]`. `EditorController.apply(_ fix: LintFix)` replaces through `shouldChangeText`/`didChangeText` so undo works. `StatusBarView.onNotesClick: (() -> Void)?`.
- Rule ids and messages are fixed by the spec's list; message copy, one sentence each, e.g. `heading-space`: "A heading needs a space after its # signs; without one this line stays a paragraph."

- [ ] **Step 1:** Write `lint-cases.json`: an array of `{ "name", "source", "rules": [ids in order], "fixed": text after applying every fix }`, at least two cases per rule plus negatives (`#hashtag` mid-sentence, a deliberate one-line setext heading `Title\n---`, a closed fence, `1.` after a paragraph, `<a b>` link).
- [ ] **Step 2:** Tests: `casesFromFixture` (rules and fixed text match each case), `fixesWorkAfterEmojiAndCRLF` (source `"😀 x\r\n#Title\r\n"` → one `heading-space`, fixed text `"😀 x\r\n# Title\r\n"`), `codeIsExempt` (`#Title` inside a fenced block and inline code gives no issue).
- [ ] **Step 3:** Run; FAIL.
- [ ] **Step 4:** Implement `lint`: one `MarkdownTree` walk for structure (paragraph line spans, setext headings, fenced blocks reaching the end, empty image alt, leftover `**`/`__` in text nodes), plus line scans limited to paragraph lines for `heading-space`, `ordered-list-interrupt`, `link-space` and `table-separator`. Ranges through `SourceMap`.
- [ ] **Step 5:** Run; PASS.
- [ ] **Step 6:** UI: issues get a wavy underline in palette `accentColor` (rendering attribute, like syntax colours); the status bar shows `N notes` when N > 0; clicking it opens a popover listing issues (message, line, a Fix button when `fix != nil`, Go to line). Option-click on an underlined range opens the same popover for that issue (Task 4 extends this click).
- [ ] **Step 7:** Bench: `swift run -c release --package-path macos LoomingsBench` insert p95 at 1 MB stays under 2 ms; parse p95 at 1 MB rises by no more than 40 ms. Record both in `macos/ACCEPTANCE.md`.
- [ ] **Step 8:** Self-test: type `#Title`, wait for analysis, expect one issue; apply its fix; text becomes `# Title`; undo restores `#Title`.
- [ ] **Step 9:** Global checks; commit `macos: learner's Markdown checker`.

### Task 4: Explain this marker (feature 3)

**Files:**
- Create: `macos/Sources/LoomingsTeaching/MarkerGlossary.swift`
- Test: `macos/Tests/LoomingsTeachingTests/MarkerGlossaryTests.swift`
- Modify: `macos/Sources/LoomingsEditor/EditorController.swift` (`span(at:)`), `TeachingPopovers.swift`, `EditorWindowController.swift`

**Interfaces:**
- Consumes: `MarkdownSyntaxKind`, `LintIssue` (Task 3).
- Produces:
  ```swift
  public struct MarkerExplanation: Equatable, Sendable { public let title: String; public let body: String; public let lesson: String? }  // lesson = "02-lists-quotes.md"
  public enum MarkerGlossary { public static func explain(kind: MarkdownSyntaxKind, marker: String) -> MarkerExplanation? }
  ```
  `EditorController.span(at location: Int) -> MarkdownSyntaxSpan?`; `EditorController.onOptionClick: ((Int) -> Void)?` (character index).
- Coverage: every `MarkdownSyntaxKind` except `codeBlockContent`; heading markers explain the level from the count of `#` (`"##"` → "Level-2 heading"); setext `===`/`---` explained separately; list markers distinguish bullet, numbered and task box (`[ ]`/`[x]`).

- [ ] **Step 1:** Tests: `headingLevelFromHashes` (`"###"` → title "Level-3 heading", lesson "01-basics.md"), `taskBox` (`"[ ]"` → title contains "Task"), `everyKindExplained` (loop over all kinds but `codeBlockContent`, non-nil).
- [ ] **Step 2:** Run; FAIL. Implement; run; PASS.
- [ ] **Step 3:** UI: option-click in the editor → if a lint issue covers the index, show the issue popover (Task 3), else if `span(at:)` finds a marker, show the explanation popover with an "Open lesson" button that opens the bundled lesson in Split (reuse the Learn menu action).
- [ ] **Step 4:** Self-test: `span(at: 0)` on `"## A"` is a `headingMarker`; explanation title is "Level-2 heading".
- [ ] **Step 5:** Global checks; commit `macos: explain a marker with option-click`.

### Task 5: Exercises that check themselves (feature 4)

**Files:**
- Create: `macos/Sources/LoomingsTeaching/ExerciseEvaluator.swift`
- Create: `lessons/checks.json` (repo root; source of truth, exported by `scripts/export-native-resources.mjs` to `macos/Resources/lessons/checks.json`)
- Modify: `scripts/export-native-resources.mjs`, `macos/scripts/build-app.sh` (copies the folder already; verify)
- Test: `macos/Tests/LoomingsTeachingTests/ExerciseEvaluatorTests.swift`, fixture `Fixtures/check-cases.json`
- Modify: `StatusBarView.swift` (clickable "Exercise 2 of 4"), `TeachingPopovers.swift`, `EditorWindowController.swift`, `AppDelegate.swift` (attach lesson checks when a lesson opens), `LoomingsDocument.swift` (`attachedChecks: [ExerciseCheck]`)

**Interfaces:**
- Consumes: `Directives`, `ExerciseCheck`, `DirectiveNote` (Task 2).
- Produces:
  ```swift
  public struct CheckResult: Equatable, Sendable { public let check: ExerciseCheck; public let label: String; public let passed: Bool; public let detail: String }  // detail "2 of 3 items"
  public enum ExerciseEvaluator {
      public static func evaluate(_ source: String, extra: [ExerciseCheck] = []) -> (results: [CheckResult], notes: [DirectiveNote])
  }
  ```
  `checks.json`: `{ "01-basics.md": ["heading 2", "emphasis", "strong"], ... }`, one array per lesson matching its "Try it" exercises; values use the directive syntax.
- Counting rules: lists count items of the first qualifying list; `nested-list` needs a list inside a list item; `words` uses `TextStatistics.countWords` on the body without frontmatter; `reference-link` needs a `[text][id]` link whose definition exists.

- [ ] **Step 1:** Fixture and tests: `casesFromFixture` (source + expected `passed` per check), `lessonChecksParse` (every value in `lessons/checks.json` parses), `frontmatterAndExtraCombine`.
- [ ] **Step 2:** Run; FAIL. Implement; PASS.
- [ ] **Step 3:** UI: when results are non-empty the status bar shows "Exercise 2 of 4" (palette `textDim`; all passed shows "Exercise done" in `accentColor`); clicking opens a checklist popover (check label, detail, tick or empty circle). Evaluation runs on the background analysis.
- [ ] **Step 4:** Self-test: open lesson 02 through the Learn action, append a three-item bullet list, wait for analysis, the bullet-list check passes.
- [ ] **Step 5:** `node scripts/export-native-resources.mjs`; global checks; commit `macos: exercises that check themselves`.

### Task 6: Section word limits (feature 9)

**Files:**
- Create: `macos/Sources/LoomingsTeaching/SectionStatistics.swift`
- Test: `macos/Tests/LoomingsTeachingTests/SectionStatisticsTests.swift`
- Modify: `StatusBarView.swift`, `EditorWindowController.swift` (status + toolbar outline menu titles)

**Interfaces:**
- Consumes: `SectionLimit` (Task 2), `OutlineItem`.
- Produces:
  ```swift
  public struct SectionCount: Equatable, Sendable { public let heading: OutlineItem; public let range: NSRange; public let words: Int; public let limit: Int? }
  public enum SectionStatistics { public static func sections(_ source: String, outline: [OutlineItem], limits: [SectionLimit]) -> [SectionCount] }
  ```
  A section runs from its heading line to the next heading of the same or higher level. Limits match headings case-insensitively after trimming.

- [ ] **Step 1:** Tests: `nestedSectionsIncludeSubsections` (an H2 count includes its H3s), `limitMatchesCaseInsensitively`, `wordsExcludeHeadingLine`.
- [ ] **Step 2:** Run; FAIL. Implement; PASS.
- [ ] **Step 3:** UI: status bar shows the caret's innermost section with a limit, "Introduction 180 of 200 words", in `accentColor` when over; outline menu items show "Title — 180/200" when limited, "Title — 180" otherwise.
- [ ] **Step 4:** Global checks; commit `macos: section word limits`.

### Task 7: Classroom projector mode (feature 6)

**Files:**
- Create: `macos/Sources/LoomingsApp/ProjectorMode.swift` (state snapshot/restore, keystroke overlay view)
- Modify: `EditorWindowController.swift`, `AppDelegate.swift` (View > Projector Mode, ⌃⌘P), `EditorController.swift` (current-line rendering attribute; hook to report formatting commands and typed line-start markers)

**Interfaces:**
- Produces: `EditorController.onMarkupUsed: ((String) -> Void)?` called with a short phrase ("Bold: **text**", "Heading 2: ## ", "Bullet list: - ", "Quote: > ", "Code block: ```"); `EditorController.highlightsCurrentLine: Bool`; `EditorWindowController.isProjectorMode: Bool`, `toggleProjectorMode(_:)`.
- Values: editor font 28 pt, preview body 26 pt, status bar and line numbers hidden, column width `.wide`, current line tinted with `selectionColor` at 0.35, overlay at bottom centre in `backgroundElevated` with `text`, 18 pt, fades after 1.6 s. Nothing in projector mode is written to `EditorPreferences`.

- [ ] **Step 1:** Implement state snapshot (font size, column width, showStats, showLineNumbers) and restore.
- [ ] **Step 2:** Self-test: toggle on, check font 28 and status hidden; toggle off, every value equals the snapshot and `UserDefaults` keys are unchanged.
- [ ] **Step 3:** Snapshot review in dark and light; global checks; commit `macos: classroom projector mode`.

### Task 8: Handout PDF and QR (feature 8)

**Files:**
- Create: `macos/Sources/LoomingsShare/ShareQRCode.swift` (CoreImage), `macos/Sources/LoomingsApp/Handout.swift` (paginated print view)
- Test: `macos/Tests/LoomingsShareTests/ShareQRCodeTests.swift`
- Modify: `EditorWindowController.swift` (Export PDF and Print use the handout; share tool becomes a menu: Copy Share Link, Show QR Code, Send with AirDrop — Task 11 fills the last)

**Interfaces:**
- Produces: `ShareQRCode.maximumBytes = 2_900`; `ShareQRCode.image(for url: URL, side: CGFloat) -> CGImage?` (nil above the limit; correction level "L"); `Handout.printView(document: PreviewDocument, title: String, shareURL: URL?, palette: ResolvedPalette?) -> NSTextView` (subclass draws "title · page n of N" in the footer via `drawPageBorder(with:)`, uses the light colours of the current family, appends the QR block "Scan to open this document in Loomings" or "This document is too long for a QR code; share it as a link").
- PDF export runs an `NSPrintOperation` with `jobDisposition = .save` to the chosen URL, A4 when the locale is metric else Letter, 36 pt margins.

- [ ] **Step 1:** Tests: `qrEncodesShortLink` (non-nil, square), `qrRefusesLongLinks` (a 3,000-byte URL → nil).
- [ ] **Step 2:** Run; FAIL. Implement; PASS.
- [ ] **Step 3:** Self-test: exported PDF of lesson 05 has more than one page (`PDFDocument(data:).pageCount > 1`) and its text contains "page 1 of".
- [ ] **Step 4:** Global checks; commit `macos: handout PDF with page numbers and a QR code`.

### Task 9: Process replay (feature 7)

**Files:**
- Create: `macos/Sources/LoomingsTeaching/HistoryLog.swift` (format, delta, reconstruction, store)
- Test: `macos/Tests/LoomingsTeachingTests/HistoryLogTests.swift`
- Create: `macos/Sources/LoomingsApp/HistoryRecorder.swift`, `macos/Sources/LoomingsApp/ReplayWindowController.swift`
- Modify: `AppDelegate.swift` (File > Writing History: Record Writing History (toggle), Replay…, Delete History…), `LoomingsDocument.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct HistoryEntry: Codable, Equatable, Sendable { public let time: TimeInterval; public let location: Int; public let deleted: Int; public let inserted: String; public let keyframe: String? }
  public enum HistoryLog {
      public static func entry(from old: String, to new: String, at time: TimeInterval) -> HistoryEntry?   // common prefix/suffix in UTF-16; nil when equal
      public static func reconstruct(_ entries: [HistoryEntry], upTo index: Int) -> String
  }
  public final class HistoryStore {
      public init(root: URL)   // default ~/Library/Application Support/Loomings/History
      public func identifier(for file: URL) throws -> String   // xattr "eu.tiagojacinto.loomings.history-id", created on first use
      public func isRecording(_ id: String) -> Bool; public func setRecording(_ id: String, _ on: Bool)
      public func append(_ entry: HistoryEntry, to id: String) throws   // JSON Lines, <id>.jsonl
      public func entries(for id: String) throws -> [HistoryEntry]
      public func delete(_ id: String) throws
  }
  ```
  A keyframe (full text) every 200 entries. Recording needs a saved document (untitled: the menu item says "Save the document to record its history").
- Recorder: on each applied analysis, if recording and at least 2 s since the last entry and text changed, append `entry(from:lastRecorded,to:current)`; on close, flush the last change.
- Replay window: read-only text view in the document's palette, a slider over entries, Play/Pause, speeds 1×, 4×, 16×, 64× (gaps over 5 s compressed to 1 s), timestamp label.

- [ ] **Step 1:** Tests: `deltaRoundTrip` (random edits including emoji, 300 steps, reconstruct equals each state), `keyframesBoundCost`, `historyFollowsRename` (id survives `FileManager.moveItem`), `deleteRemovesFile`, `notRecordingByDefault`.
- [ ] **Step 2:** Run; FAIL. Implement; PASS.
- [ ] **Step 3:** Self-test: save a temp document, turn recording on, make three edits with 2 s spacing simulated through an injectable clock, entries count 3, reconstruct last equals text; Delete History removes the file.
- [ ] **Step 4:** Global checks; commit `macos: opt-in writing history and replay`.

### Task 10: Compare With (feature 5)

**Files:**
- Create: `macos/Sources/LoomingsTeaching/LineDiff.swift`
- Test: `macos/Tests/LoomingsTeachingTests/LineDiffTests.swift`
- Create: `macos/Sources/LoomingsApp/CompareWindowController.swift`
- Modify: `AppDelegate.swift` (File > Compare With… lists other open documents and "Choose File…")

**Interfaces:**
- Produces:
  ```swift
  public enum DiffOp: Equatable, Sendable { case same(old: Int, new: Int), removed(old: Int), added(new: Int) }   // line indices
  public enum LineDiff {
      public static func lines(old: [Substring], new: [Substring]) -> [DiffOp]   // Myers O(ND), linear space
      public static func words(old: Substring, new: Substring) -> (removed: [Range<String.Index>], added: [Range<String.Index>])
  }
  ```
- Window: two read-only monospace text views side by side (left: the other document, right: the front document), synchronised scrolling, removed lines tinted `accentColor` at 0.18, added lines `linkColor` at 0.18, word changes in a removed/added pair underlined; header shows both titles and "12 lines changed".

- [ ] **Step 1:** Tests: `identicalHasNoChanges`, `insertionAndDeletion` (exact op list for a 5-line case), `largeDiffIsFast` (20,000 lines with 200 scattered edits under 1 s), `wordsInsideChangedLine`.
- [ ] **Step 2:** Run; FAIL. Implement; PASS.
- [ ] **Step 3:** Self-test: compare two in-memory documents, window opens, header reports the expected count.
- [ ] **Step 4:** Global checks; commit `macos: compare a document with another`.

### Task 11: Send with AirDrop (feature 10)

**Files:**
- Modify: `EditorWindowController.swift` (share menu item), `LoomingsDocument.swift` (temporary `.md` export for untitled/shelf documents in `FileManager.default.temporaryDirectory/Loomings Send/`)

**Interfaces:**
- Consumes: share menu from Task 8.
- Produces: `EditorWindowController.sendWithAirDrop(_:)`: `NSSharingService(named: .sendViaAirDrop)` with the file URL; disabled (with tooltip) when `canPerform(withItems:)` is false.

- [ ] **Step 1:** Implement; temporary files are removed when the window closes.
- [ ] **Step 2:** Self-test: the menu item exists and its validation matches `canPerform`.
- [ ] **Step 3:** Global checks; update `macos/ACCEPTANCE.md` (features table, untested environments: AirDrop and multi-display projector not automated) and `CLAUDE.md` (new target, fixtures, directive syntax); commit `macos: send with AirDrop; teaching features documented`.

---

The web port of features 1, 2, 3, 4, 6, 8 and 9 is a separate plan, written after this one lands, against the same fixtures.
