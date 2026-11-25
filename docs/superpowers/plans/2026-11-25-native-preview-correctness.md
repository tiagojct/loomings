# Native Preview Correctness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent frontmatter, nested blocks, reference links, URL links, and citation marks from corrupting native preview output.

**Architecture:** Parse blanked frontmatter through `ParsedMarkdown`. Render nested blocks through one recursive path. Key the preview cache by resolved link destinations. Disallow overlapping link matches. Map late citation reports through exact edit deltas.

**Tech Stack:** Swift 5 language mode, SwiftPM, AppKit, TextKit, cmark-gfm.

**Spec:** `docs/superpowers/specs/2026-11-24-stabilization-design.md`

## Global Constraints

- Preserve public APIs unless a task explicitly extends them.
- Add a Swift Testing regression test before each behavioral fix.
- Run `swift test --package-path macos` after each task.
- Keep native-only work separate from web release numbering.
- Do not commit `macos/plans/`.
- Preserve byte-for-byte parity with existing web HTML fixtures.
- Run the native self-test only on an awake, unlocked Mac.

## Review Focus

- Frontmatter with an unclosed fence must not hide the document body. Task 1 pins this.
- Nested blocks in lists and quotes must keep their text and styles. Task 2 pins this.
- Multiline reference edits must invalidate cached link blocks. Task 3 pins this.
- A URL with email user information must not produce duplicate links. Task 4 pins this.
- An old citation report must not reapply after the source changes. Task 5 pins this.

---

### Task 1: Blank frontmatter before native parsing

**Files:**
- Modify: `macos/Sources/LoomingsMarkdown/ParsedMarkdown.swift:8-34`
- Modify: `macos/Sources/LoomingsMarkdown/MarkdownParser.swift:6-55`
- Modify: `macos/Sources/LoomingsPreview/PreviewRenderer.swift:55-86`
- Test: `macos/Tests/LoomingsMarkdownTests/MarkdownParserTests.swift`
- Create: `macos/Tests/LoomingsPreviewTests/Fixtures/frontmatter-fence.md`
- Create: `macos/Tests/LoomingsPreviewTests/Fixtures/frontmatter-fence.html`

**Interfaces:**
- Produces: `ParsedMarkdown.parsedText: String`, the blanked text used for parsing.
- `MarkdownParser.parse` and `PreviewRenderer.render` consume `ParsedMarkdown`.

- [ ] **Step 1: Add failing frontmatter fixtures and parser tests**

Cover:

- `title: "```"` inside frontmatter does not swallow a later heading.
- A reference definition inside frontmatter does not resolve a body link.
- Non-ASCII and emoji frontmatter preserves later UTF-16 ranges.
- Existing outline and frontmatter tests still pass.

- [ ] **Step 2: Run focused tests**

Run: `swift test --package-path macos --filter 'MarkdownParserTests|PreviewHTMLTests'`
Expected: FAIL because raw frontmatter reaches cmark.

- [ ] **Step 3: Expose and use the blanked parse text**

Store the blanked string in `ParsedMarkdown.parsedText`.
Build `SourceMap` and `MarkdownTree` from `parsedText`.
Use `ParsedMarkdown` in `MarkdownParser.parse` and `PreviewRenderer.render`.
Scan reference definitions from `parsedText`, not original frontmatter.

- [ ] **Step 4: Regenerate HTML fixtures**

Run: `node macos/scripts/render-web-fixtures.mjs`
Expected: the new fixture matches web output and existing fixtures stay unchanged.

- [ ] **Step 5: Run focused and full Swift tests**

Run: `swift test --package-path macos`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/LoomingsMarkdown/ParsedMarkdown.swift macos/Sources/LoomingsMarkdown/MarkdownParser.swift macos/Sources/LoomingsPreview/PreviewRenderer.swift macos/Tests/LoomingsMarkdownTests/MarkdownParserTests.swift macos/Tests/LoomingsPreviewTests/Fixtures/frontmatter-fence.md macos/Tests/LoomingsPreviewTests/Fixtures/frontmatter-fence.html
git commit -m "fix: blank frontmatter before native parsing"
```

---

### Task 2: Render nested blocks recursively

**Files:**
- Modify: `macos/Sources/LoomingsPreview/PreviewRenderer.swift:209-219,313-462,1003-1064`
- Test: `macos/Tests/LoomingsPreviewTests/PreviewAttributedTests.swift`
- Create: `macos/Tests/LoomingsPreviewTests/Fixtures/nested-blocks.md`
- Create: `macos/Tests/LoomingsPreviewTests/Fixtures/nested-blocks.html`

**Interfaces:**
- `renderList`, `renderQuote`, `blockChildrenHTML`, and `listHTML` receive `map` and `source`.
- Nested block rendering preserves existing source ranges and line numbers.

- [ ] **Step 1: Add failing nested-block fixtures and attributed tests**

Cover:

- Fenced code inside a blockquote keeps its language and source line.
- Lists inside quotes render in attributed text and HTML.
- Headings, tables, rules, and code inside list items or quotes keep their text.
- A code block inside a quote keeps its own `NSTextBlock`.
- Existing tight and loose list HTML remains byte-for-byte identical.

- [ ] **Step 2: Run focused tests**

Run: `swift test --package-path macos --filter 'PreviewAttributedTests|PreviewHTMLTests'`
Expected: FAIL because nested block types are dropped.

- [ ] **Step 3: Thread source context through recursive renderers**

Pass the real `SourceMap` and source string into list, quote, and HTML child renderers.
Delegate every supported block type to the existing block renderer.
Preserve tight-list newline placement from the web fixtures.

- [ ] **Step 4: Compose quote paragraph styles**

Copy each existing paragraph style.
Prepend the quote border block and adjust indents per style run.
Do not overwrite child list, code, table, or nested-quote styles.

- [ ] **Step 5: Regenerate fixtures and run full Swift tests**

Run: `node macos/scripts/render-web-fixtures.mjs && swift test --package-path macos`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/LoomingsPreview/PreviewRenderer.swift macos/Tests/LoomingsPreviewTests/PreviewAttributedTests.swift macos/Tests/LoomingsPreviewTests/Fixtures/nested-blocks.md macos/Tests/LoomingsPreviewTests/Fixtures/nested-blocks.html
git commit -m "fix: render nested native preview blocks"
```

---

### Task 3: Invalidate cache from resolved reference links

**Files:**
- Modify: `macos/Sources/LoomingsPreview/PreviewRenderer.swift:29-75`
- Test: `macos/Tests/LoomingsPreviewTests/PreviewCacheTests.swift:148-156`

**Interfaces:**
- Produces: `CacheKey.definitions: String`.
- Produces: `resolvedLinkKey(for tree: MarkdownTree) -> String`.

- [ ] **Step 1: Add failing cache tests**

Cover:

- A URL on the second line of a reference definition changes the rendered link.
- A title on a continuation line changes the HTML title and tooltip.
- A blockquote reference definition invalidates a body link.
- A reference-looking line inside a code fence does not affect the key.
- A body edit still reuses all unchanged blocks.

- [ ] **Step 2: Run cache tests**

Run: `swift test --package-path macos --filter PreviewCacheTests`
Expected: FAIL for multiline and blockquote definitions.

- [ ] **Step 3: Build the key from cmark-resolved links**

Walk link and image nodes after parsing.
Collect each resolved destination and title.
Sort the values and join them with unambiguous separators.
Use the resulting string in `CacheKey` instead of a 64-bit hash.

- [ ] **Step 4: Run cache and full Swift tests**

Run: `swift test --package-path macos`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/LoomingsPreview/PreviewRenderer.swift macos/Tests/LoomingsPreviewTests/PreviewCacheTests.swift
git commit -m "fix: invalidate preview cache from resolved links"
```

---

### Task 4: Prevent overlapping links and linearize URL trimming

**Files:**
- Modify: `macos/Sources/LoomingsPreview/PreviewSupport.swift:366-463`
- Test: `macos/Tests/LoomingsPreviewTests/PreviewCacheTests.swift:193-229`
- Test: `macos/Tests/LoomingsPreviewTests/PreviewAttributedTests.swift`

**Interfaces:**
- `Linkifier.matches(in:)` keeps its signature.
- Matches become disjoint and sorted.
- `trimmed(_:in:)` keeps its signature and runs in linear time.

- [ ] **Step 1: Add failing link tests**

Cover:

- `https://user@example.com/path` produces one URL link and no mail link.
- Two URLs with email-shaped paths produce exactly two links.
- HTML contains no duplicated URL suffix.
- Balanced parentheses remain intact.
- A URL followed by 10,000 closing parentheses completes in under 5 ms.

- [ ] **Step 2: Run focused tests**

Run: `swift test --package-path macos --filter 'FastPathTests|PreviewAttributedTests'`
Expected: FAIL for overlap and performance.

- [ ] **Step 3: Discard overlapping email matches**

Keep URL matches.
Add an email match only when its range intersects no accepted match.
Sort the final disjoint matches by location.

- [ ] **Step 4: Count parentheses once**

Trim trailing punctuation with UTF-16 switches.
Count opening and closing parentheses in one pass.
Decrement the closing count while stripping unmatched trailing parentheses.

- [ ] **Step 5: Run full Swift tests**

Run: `swift test --package-path macos`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/LoomingsPreview/PreviewSupport.swift macos/Tests/LoomingsPreviewTests/PreviewCacheTests.swift macos/Tests/LoomingsPreviewTests/PreviewAttributedTests.swift
git commit -m "fix: prevent overlapping links and quadratic trimming"
```

---

### Task 5: Restore citation marks only for the exact reported source

**Files:**
- Modify: `macos/Sources/LoomingsApp/EditorWindowController.swift:384-439`
- Test: `macos/Tests/LoomingsEditorTests/EditorControllerTests.swift:785-860`
- Test: `macos/Sources/LoomingsApp/SelfTest.swift`

**Interfaces:**
- `updateCitations` restores the last report only when `editor.source == latest.source`.
- Existing `setCitations` mapping remains unchanged.

- [ ] **Step 1: Add failing citation-mark tests**

Cover:

- An edit inside a citation followed by another edit does not reapply the old report.
- The untouched citation mark moves with the second edit.
- Undo to the exact reported source restores the dropped mark immediately.
- A changed source does not restore marks from an older report.

- [ ] **Step 2: Run focused tests**

Run: `swift test --package-path macos --filter CitationMarkTests`
Expected: FAIL because `updateCitations` compares only mark counts.

- [ ] **Step 3: Add the exact-source guard**

Restore the last report only when the editor source equals the reported source.
Keep the existing note-count update.
Do not change late-report mapping in this task.

- [ ] **Step 4: Add a self-test check**

Edit inside a citation, then edit elsewhere.
Run a parse before the next citation report.
Assert the untouched mark remains and moves to the correct range.

- [ ] **Step 5: Run full Swift tests and build the app**

Run: `swift test --package-path macos && swift build --package-path macos --product LoomingsApp`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/LoomingsApp/EditorWindowController.swift macos/Tests/LoomingsEditorTests/EditorControllerTests.swift macos/Sources/LoomingsApp/SelfTest.swift
git commit -m "fix: restore citation marks only for the reported source"
```

Known limitation: a late report after multiple disjoint edits can still drop untouched marks. A later task must add exact multi-edit mapping.

---

## Final verification

- [ ] Run `swift test --package-path macos`.
- [ ] Run `node macos/scripts/render-web-fixtures.mjs`.
- [ ] Confirm `git diff --exit-code` after fixture regeneration.
- [ ] Run `./macos/scripts/build-app.sh`.
- [ ] Run the native `--self-test`.
- [ ] Review the new preview fixtures against the web renderer.
