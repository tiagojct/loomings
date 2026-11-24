# Native Data Safety Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent encoding corruption, history deadlocks, local-image disclosure, missing handout images, and undecodable share links.

**Architecture:** The text codec rejects ambiguous encodings. History deletion uses scoped locking. Image loading receives an explicit trust flag. A shared resolver fills handout attachments. Share encoding checks the decoded limit before compression.

**Tech Stack:** Swift 5 language mode, SwiftPM, AppKit, ImageIO, JavaScriptCore, zlib.

**Spec:** `docs/superpowers/specs/2026-11-24-stabilization-design.md`

## Global Constraints

- Preserve public APIs unless a task explicitly extends them.
- Add a Swift Testing regression test before each behavioral fix.
- Run `swift test --package-path macos` after each task.
- Keep native-only work separate from web release numbering.
- Do not commit `macos/plans/`.
- Run the native self-test only on an awake, unlocked Mac.

## Review Focus

- Open a UTF-32LE file that begins with `FF FE 00 00`. The app must refuse it. Task 1 pins this.
- Fail history file deletion. The next store operation must not block. Task 2 pins this.
- Open an unsaved share link with an absolute local image. Preview and DOCX must not read it. Task 3 pins this.
- Print a local document with a local image and a data image. Both must appear. Task 4 pins this.
- Encode highly compressible text above 8 MB. Encoding must fail before producing a link. Task 5 pins this.

---

### Task 1: Refuse ambiguous text encodings

**Files:**
- Modify: `macos/Sources/LoomingsDocuments/TextFile.swift:69-123`
- Test: `macos/Tests/LoomingsDocumentsTests/TextFileTests.swift:65-79`

**Interfaces:**
- Consumes: existing `TextFileCodec.decode(_:)`.
- Produces: `TextFileError.unsupportedEncoding` for UTF-32 and BOMless UTF-16 input.

- [ ] **Step 1: Write failing encoding tests**

Add tests for:

- UTF-32LE BOM: `FF FE 00 00`.
- UTF-32BE BOM: `00 00 FE FF`.
- BOMless UTF-16LE ASCII text.
- BOMless UTF-16BE ASCII text.
- Valid UTF-8 text containing no NUL bytes still opens.

- [ ] **Step 2: Run the codec tests**

Run: `swift test --package-path macos --filter TextFileTests`
Expected: FAIL because UTF-32LE is accepted as UTF-16LE and BOMless UTF-16 is accepted as UTF-8.

- [ ] **Step 3: Reject UTF-32 before UTF-16 detection**

Check both UTF-32 BOMs before the UTF-16 branches.
Throw `unsupportedEncoding`.

- [ ] **Step 4: Reject NUL bytes in BOMless input**

Before UTF-8 decoding, reject data containing byte `0x00`.
Keep the existing Latin-1 refusal behavior.

- [ ] **Step 5: Run the codec tests**

Run: `swift test --package-path macos --filter TextFileTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/LoomingsDocuments/TextFile.swift macos/Tests/LoomingsDocumentsTests/TextFileTests.swift
git commit -m "fix: refuse ambiguous native text encodings"
```

---

### Task 2: Release the history lock on deletion failure

**Files:**
- Modify: `macos/Sources/LoomingsTeaching/HistoryLog.swift:78-93,252-261`
- Modify: `macos/Sources/LoomingsApp/HistoryRecorder.swift:96-110`
- Test: `macos/Tests/LoomingsTeachingTests/HistoryLogTests.swift:98-109`

**Interfaces:**
- Produces: `HistoryStore(root:fileManager:)` with `FileManager.default` as the default.
- Produces: `delete(_:)` releases its lock on every exit path.
- `HistoryRecorder` reports deletion failure through `onError`.

- [ ] **Step 1: Write the failure-injection test**

Add a `FileManager` subclass whose `removeItem(at:)` throws.
Create a recorded history entry.
Expect `store.delete("doc")` to throw.
Then call `store.entries(for: "doc")` and `store.isRecording("doc")`.
Both calls must return without deadlock.

- [ ] **Step 2: Run the history tests with a timeout**

Run: `swift test --package-path macos --filter HistoryLogTests`
Expected: FAIL or time out because the throwing path skips `unlock`.

- [ ] **Step 3: Use scoped locking**

Add an injectable `FileManager`.
Use `lock.lock()` followed by `defer { lock.unlock() }`.
Call `setRecording` after the lock scope ends.

- [ ] **Step 4: Report recorder deletion failures**

Replace `try?` in both `HistoryRecorder.deleteHistory` methods with `do/catch`.
Call `onError` with the localized failure.

- [ ] **Step 5: Run history tests**

Run: `swift test --package-path macos --filter HistoryLogTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/LoomingsTeaching/HistoryLog.swift macos/Sources/LoomingsApp/HistoryRecorder.swift macos/Tests/LoomingsTeachingTests/HistoryLogTests.swift
git commit -m "fix: release history lock after deletion failure"
```

---

### Task 3: Block local images from unsaved shared documents

**Files:**
- Modify: `macos/Sources/LoomingsPreview/PreviewImageLoader.swift:26-49`
- Modify: `macos/Sources/LoomingsApp/PreviewTextView.swift:166-173,401-433`
- Modify: `macos/Sources/LoomingsDocx/DocxExport.swift:24-36,87-90,337-345`
- Modify: `macos/Sources/LoomingsApp/EditorWindowController.swift:758-811,1547-1568,1872-1879`
- Test: `macos/Tests/LoomingsPreviewTests/ImageLoaderTests.swift:36-66`
- Test: `macos/Tests/LoomingsDocxTests/DocxExportTests.swift:128-147`

**Interfaces:**
- Produces: `PreviewImageLoader.load(..., allowImagePaths: Bool = true)`.
- Produces: `PreviewTextView.render(source:documentURL:allowImagePaths:)`.
- Produces: `PreviewTextView.render(_:documentURL:allowImagePaths:)`.
- Produces: `DocxExport.data(..., allowImagePaths: Bool = true)`.
- `allowImagePaths = false` permits data images only.

- [ ] **Step 1: Write failing image-trust tests**

Add tests that:

- An absolute PNG path returns `.blocked` when `allowImagePaths` is false.
- A `file://` URL returns `.blocked` when `allowImagePaths` is false.
- A data URI still loads when `allowImagePaths` is false.
- A local document still loads a relative image with the default value.
- DOCX export with `allowImagePaths = false` contains no `word/media/image*.png`.
- DOCX export still embeds a data URI when paths are blocked.

- [ ] **Step 2: Run image and DOCX tests**

Run: `swift test --package-path macos --filter 'ImageLoaderTests|DocxExportTests'`
Expected: FAIL because the trust parameter does not exist.

- [ ] **Step 3: Add the loader trust gate**

After the data-URI branch, block every path when `allowImagePaths` is false.
Keep remote-image blocking unchanged.

- [ ] **Step 4: Carry trust through preview and DOCX**

Add `allowImagePaths` to `PreviewTextView` render state.
Pass `citationPathsAllowed` from `EditorWindowController`.
Capture the flag in `ExportPage`.
Pass it to `DocxExport.data`.
Pass it to the DOCX writer and image loader.

- [ ] **Step 5: Run image and DOCX tests**

Run: `swift test --package-path macos --filter 'ImageLoaderTests|DocxExportTests'`
Expected: PASS.

- [ ] **Step 6: Add a self-test check**

Open an unsaved shared document with an absolute image path.
Assert the preview shows a blocked placeholder.
Export DOCX and assert it contains no media image.

- [ ] **Step 7: Commit**

```bash
git add macos/Sources/LoomingsPreview/PreviewImageLoader.swift macos/Sources/LoomingsApp/PreviewTextView.swift macos/Sources/LoomingsDocx/DocxExport.swift macos/Sources/LoomingsApp/EditorWindowController.swift macos/Sources/LoomingsApp/SelfTest.swift macos/Tests/LoomingsPreviewTests/ImageLoaderTests.swift macos/Tests/LoomingsDocxTests/DocxExportTests.swift
git commit -m "fix: block local images in unsaved shared documents"
```

---

### Task 4: Resolve handout images before layout

**Files:**
- Create: `macos/Sources/LoomingsPreview/PreviewImageResolver.swift`
- Modify: `macos/Sources/LoomingsApp/Handout.swift:40-70`
- Modify: `macos/Sources/LoomingsApp/EditorWindowController.swift:1762-1772`
- Test: `macos/Tests/LoomingsPreviewTests/PreviewImageResolverTests.swift`

**Interfaces:**
- Produces: `PreviewImageResolver.resolve(_:documentURL:allowImagePaths:) -> NSAttributedString`.
- Produces: `Handout.view(..., allowImagePaths: Bool = true)`.
- The resolver replaces placeholder attachments with decoded images.
- Blocked and missing images keep their placeholders.

- [ ] **Step 1: Write failing resolver tests**

Create an attributed string with:

- A local image placeholder.
- A data-URI image placeholder.
- A blocked absolute image placeholder.

Assert that:

- The local image resolves to its pixel size.
- The data image resolves to its pixel size.
- The blocked image remains a placeholder when paths are disallowed.

- [ ] **Step 2: Run the new test file**

Run: `swift test --package-path macos --filter PreviewImageResolverTests`
Expected: FAIL because the resolver does not exist.

- [ ] **Step 3: Implement the shared resolver**

Copy the attributed string.
Enumerate `.loomingsImageURL`.
Load each source with `PreviewImageLoader`.
Replace the `.attachment` with an `NSTextAttachment` containing the decoded image.
Preserve the existing attachment bounds.

- [ ] **Step 4: Use the resolver in Handout**

Resolve `rendered.attributed` before appending the QR block.
Pass `allowImagePaths` from `ExportPage`.

- [ ] **Step 5: Add a PDF image test**

Build a handout from a local image and a data image.
Write a PDF.
Assert the PDF data contains `/Subtype /Image`.
Assert a text-only PDF does not contain that marker.

- [ ] **Step 6: Run preview tests**

Run: `swift test --package-path macos --filter 'PreviewImageResolverTests|ImageLoaderTests'`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add macos/Sources/LoomingsPreview/PreviewImageResolver.swift macos/Sources/LoomingsApp/Handout.swift macos/Sources/LoomingsApp/EditorWindowController.swift macos/Tests/LoomingsPreviewTests/PreviewImageResolverTests.swift macos/Sources/LoomingsApp/SelfTest.swift
git commit -m "fix: include images in native handouts and PDF export"
```

---

### Task 5: Reject share input above the decoded limit

**Files:**
- Modify: `macos/Sources/LoomingsShare/ShareLink.swift:43-63`
- Test: `macos/Tests/LoomingsShareTests/ShareLinkTests.swift:116-130`

**Interfaces:**
- Consumes: `ShareLink.maximumDecodedLength`.
- Produces: `ShareLink.encode(_:)` throws `ShareLinkError.tooLarge` before compression when raw UTF-8 exceeds the limit.

- [ ] **Step 1: Write the compressed-oversize test**

Create text whose UTF-8 data exceeds 8,000,000 bytes but compresses below 4,000,000 bytes.
Use a repeated ASCII line.
Expect `ShareLink.encode` to throw `tooLarge`.

- [ ] **Step 2: Run the share tests**

Run: `swift test --package-path macos --filter ShareLinkTests`
Expected: FAIL because encoding succeeds.

- [ ] **Step 3: Check raw size before compression**

After UTF-8 conversion, guard `raw.count <= maximumDecodedLength`.
Throw `tooLarge` before calling `RawDeflate.deflate`.

- [ ] **Step 4: Run the share tests**

Run: `swift test --package-path macos --filter ShareLinkTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/LoomingsShare/ShareLink.swift macos/Tests/LoomingsShareTests/ShareLinkTests.swift
git commit -m "fix: reject native share input above decoded limit"
```

---

## Final verification

- [ ] Run `swift test --package-path macos`.
- [ ] Build with `./macos/scripts/build-app.sh`.
- [ ] Run the native self-test on an awake, unlocked Mac.
- [ ] Open a UTF-32LE file and confirm refusal.
- [ ] Open an unsaved share link with an absolute image and confirm it stays blocked.
- [ ] Export a local document with images to PDF and confirm the images appear.
