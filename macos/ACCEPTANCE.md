# Native macOS acceptance — Stage 6

Personal-use build, functional parity with web release 2.3.0. This is a
stage report, not a claim that every target passed; failures and unavailable
environments are listed explicitly.

## Environment

- Machine: MacBookPro17,1, Apple Silicon, 8 GB, macOS 15.8 (24H23), 1920×1080 @ 75 Hz.
- Toolchain: Swift 6.1.2, Command Line Tools only; no full Xcode. UI automation that
  needs Xcode is unavailable.
- Web release: 2.3.0. Native bundle: `eu.tiagojacinto.loomings.native`, macOS 15.0+,
  arm64 only, about 4 MB on disk.
- Signing: ad-hoc (`codesign -dv` reports `Signature=adhoc`, no Team ID). This is
  local development signing, not Developer ID, and the app is not notarised.

## Build and data

One command builds an optimised arm64 bundle:

```sh
./macos/scripts/build-app.sh          # macos/dist/Loomings.app
```

To install for personal use:

```sh
# Quit a running copy first if there is one.
osascript -e 'quit app "Loomings"' 2>/dev/null || true
rm -rf /Applications/Loomings.app
ditto macos/dist/Loomings.app /Applications/Loomings.app
open /Applications/Loomings.app
```

The build is ad-hoc signed and has no quarantine flag. If macOS still blocks the first
launch, use System Settings → Privacy & Security → Open Anyway (or right-click the app
and choose Open); do not disable Gatekeeper globally. On macOS 15+, Apple Silicon only.

Documents stay wherever the user saves them. Untitled/browser-style documents use
`~/Library/Application Support/Loomings/Shelf/`; preferences use the app's
`UserDefaults` domain. Replacing the `.app` does not touch either.

Verified by creating a shelf document titled “Persistence Test” and selecting Goney
dark, replacing the app, then launching the new build: the Goney checkmark, the shelf
menu entry and the document title all survived. The test entry and theme selection were
removed afterwards.

## Parity checklist

| Area | Status | Evidence |
|---|---|---|
| Open, Save, Save As, Duplicate, Rename, Open Recent | Yes | NSDocument plumbing; menus; save/encoding/autosave tests |
| Drag and drop files | Yes | Scroll-view destination; not automated |
| UTF-8/UTF-16 BOM and LF/CRLF preservation | Yes | Codec tests and document round trips |
| Unsupported encodings refused | Yes | Codec and shelf import tests |
| Autosave, versions, recovery | Partial | Autosave-in-place test; untitled recovery is NSDocument's; a real crash was not simulated |
| External modifications | Partial | Detector tests; activation sheet not automated |
| Independent windows and tabs | Yes | Native tabs, visual check |
| Local shelf with stable IDs, atomic writes, import | Yes | Shelf tests, save/open, browser-export import |
| Formatting shortcuts and toggles | Yes | Unit tests and self-test |
| List/quote continuation, Tab indent | Yes | Unit tests and self-test |
| Smart typography | Yes | Unit tests and self-test |
| Frontmatter dimmed in editor, omitted in preview | Yes | Parser, editor and fixture tests |
| Native find/replace | Yes | Find bar and menu; replacement undo is NSTextView's |
| Outline including setext headings | Yes | Parser, menu, navigation self-test |
| Statistics, reading time, word goal | Yes | Status bar, self-test, themed GUI run |
| Font size, column width, line numbers | Yes | Menus, preferences, visual checks |
| Focus mode, typewriter, full screen | Yes | Self-tests and visual checks |
| Spelling services, accessibility labels | Yes | Spelling remains enabled; AX labels checked |
| Native preview: headings, inline, lists, quotes, code, rules | Yes | Preview fixtures and visual checks |
| Tables and images | Yes | NSTextTable, async attachments, visual checks |
| Linkify, typographer, URL sanitisation | Yes | Nine byte-for-byte web HTML fixtures |
| Frontmatter omitted; raw HTML literal | Yes | Fixtures |
| Relative images; missing images | Yes | Document-directory resolution; placeholder |
| Source mapping and bidirectional split sync | Yes | Self-test |
| Incremental view updates; scroll preservation | Yes | Block diffing; top source line restored |
| Markdown, HTML, PDF, Print export | Yes | HTML/PDF tested; print panel not automated |
| Ten Ensigns palettes and System/Light/Dark | Yes | Exported JSON, contrast tests, theme menu |
| JetBrains Mono and Source Serif 4 | Yes | Bundled TTF + OFL; self-test finds both |
| Lessons, example, cheatsheet | Yes | Learn menu; lessons open in new Split windows |
| Share links `#d=p.` / `#d=z.` | Yes | Raw DEFLATE, limits, Node↔Swift tests |
| Share link copy/open and family/mode import | Yes | Copy tested; Open Share Link modal not automated |
| About and Ensigns attribution | Yes | About panel |

## Verification

- `swift test --package-path macos`: 88 tests pass.
- `Loomings --self-test`: 93 checks pass, exit 0.
- `npm test`: 189 tests pass; `npm run typecheck`: clean; `npm run build`: succeeds.
- Share interop runs the web decoder through Node from the Swift suite, and Swift
  decodes web-generated fixtures.
- Visual checks: Pequod dark, Rosebud light, Goney dark, themed preview, line numbers,
  lesson in Split, table/image preview, About panel, light status bar, and the
  Adamastor-style native icon at 1024/256/64 px.
- Keyboard: ⌘\ split, ⌘⇧P preview, formatting shortcuts, menu navigation.
- VoiceOver: toggled on and off while the app was running; editor and preview carry
  accessibility labels. Full VoiceOver reading order/navigation was not scripted.

## Performance, themed (Pequod dark)

Release build, 10 KB / 100 KB / 1 MB / 10 MB mixed corpus. The editor had a resolved
palette; preview rendering was measured separately; the GUI run had statistics and
Split preview visible.

| Corpus | Parse p95 | Insert p95 | Handler p95 | Visible styling | Preview render p95 | Footprint |
|---:|---:|---:|---:|---:|---:|---:|
| 10 KB | 3.45 ms | 0.81 ms | <0.01 ms | 8.8 ms | 18.1 ms | 55 MB |
| 100 KB | 33.3 ms | 0.83 ms | <0.01 ms | 6.4 ms | 184.2 ms | 109 MB |
| 1 MB | 351 ms | 0.96 ms | 0.01 ms | 6.9 ms | 2.19 s | 184 MB |
| 10 MB | 3.99 s | 1.06 ms | 0.01 ms | 24.9 ms | 32.6 s | 468 MB |

Startup with theme: 867 ms.

- Edit-handler target (<8 ms p95 through 1 MB): pass.
- Typing independent of parsing: pass; insert p95 stays around 1 ms at 10 MB.
- Scroll styling: 0.01–0.04 ms p95; no layout invalidation on pure scroll.
- Preview, cold render (table above) versus an edit of one block with the block cache
  (`swift run -c release LoomingsBench --preview`, p95): 2.4 ms at 10 KB, 26.7 ms at
  100 KB, 289 ms at 1 MB; a cold render is 20 ms, 212 ms and 2.2 s. Of the 285 ms at
  1 MB, about 210 ms was swift-markdown building its Swift tree.

## Performance after the cmark pass (2026-11-01)

swift-markdown is gone: the editor parser and the preview read cmark-gfm's nodes in
place (`MarkdownTree`). The live preview no longer builds HTML (export renders from
scratch with HTML), Typographer and Linkifier skip text that cannot change, and
converted fonts are cached per theme. Same machine, release build, Pequod dark.

| Corpus | Editor parse p95 | Preview cold p95 | Preview edit p95 | HTML export | Footprint |
|---:|---:|---:|---:|---:|---:|
| 10 KB | 0.85 ms (was 3.45) | 3.8 ms (was 20) | 0.46 ms (was 2.4) | 5.6 ms | 60 MB |
| 100 KB | 8.96 ms (was 33.3) | 38.2 ms (was 212) | 4.35 ms (was 26.7) | 55 ms | 124 MB |
| 1 MB | 90.9 ms (was 351) | 398 ms (was 2.2 s) | 51.5 ms (was 289) | 581 ms | 187 MB |
| 10 MB | 931 ms (was 3.99 s) | 4.72 s (was 32.6 s) | 538 ms | 6.5 s | 459 MB |

- The 150 ms preview edit target now passes through 1 MB (51.5 ms). It misses at
  10 MB (538 ms), which stays off the main thread.
- Spans and outlines were compared between the old and new parser on 3,001 Markdown
  files from the workspace: identical. `nodeCount` is one lower per table because
  swift-markdown added a synthetic table-body node; it is a diagnostic only.
- Memory at 10 MB is unchanged (459 MB); it is dominated by TextKit, not the parse.
- Memory at 10 MB is 468 MB (616 MB after the long-line parse pass). A baseline build
  of the same corpus showed no regression (881 MB against 931 MB in the earlier run), so
  this is the per-line structure overhead of the parse (roughly 80 bytes per source
  byte on short lines), not a leak. No optimisation was made.
- Remote images are not fetched. The preview shows a placeholder, as the web CSP does.
  Local images and `data:` URIs are size-capped and decoded at preview width.

## Teaching report (2026-11-01)

The learner's checker (and, later, exercise checks and section limits) runs
as the editor's companion analysis: on its own queue, side by side with the
parse, joined before the result is delivered. It never runs on the edit path.

| Corpus | Teaching report | Editor insert p95 with it |
|---:|---:|---:|
| 10 KB | 1.0 ms | 0.78 ms |
| 100 KB | 9.5 ms | 0.90 ms |
| 1 MB | 62 ms | 0.79 ms |
| 10 MB | 663 ms | 0.78 ms |

At 1 MB the report (62 ms) finishes before the parse (91 ms), so it adds no
waiting time; at 10 MB likewise (663 ms against 930 ms). Measured with
`LoomingsBench --teaching` and the full bench, release build.

## Accessibility and OS matrix

- VoiceOver: app launched with VoiceOver on and quit cleanly; editor/preview labels and
  standard AppKit controls are present. Full VoiceOver traversal was not automated.
- Keyboard navigation: menu shortcuts and mode switching exercised; dialogs are native.
- Increased contrast: not toggled. Palette colours are fixed Ensigns values, as on the
  web; native controls adapt through AppKit.
- Reduced motion: no custom animations are added; full-screen/theme changes use system
  behaviour. Not exercised with the system setting on.
- macOS 15.8 is the only available environment. A newer macOS and Intel are untested and
  unavailable; Apple Silicon-only is intentional.

## Deferred

- Developer ID signing, notarisation, Sparkle updates and public distribution are
  deferred as agreed. The current bundle must not be described as trusted distribution.
- No web deployment was made for native-only work.

## Known gaps

1. The preview misses the 150 ms edit target at 10 MB (538 ms); it passes through 1 MB.
2. Large-file memory is high (468 MB at 10 MB) and was not optimised.
3. Crash recovery relies on NSDocument; it was not simulated end-to-end.
4. Drag-and-drop, the external-change activation sheet, the unsaved-changes sheet and
   the Open Share Link dialog are not covered by UI automation. Their logic is covered
   by `ShareLink.parse` and file-change detector tests, and a clean document reloading
   after an external change is covered by the self-test.
5. HTML export names Source Serif 4/JetBrains Mono and does not embed the fonts, so
   recipients fall back to Georgia/monospace. This is deliberate: embedding adds about
   a megabyte per file.
6. `.github/workflows/macos.yml` has not run yet and does not run the self-test, which
   needs a window server.

## Changes in the audit pass

- Save to Shelf is limited to untitled and shelf documents; before, it moved a file
  document onto the shelf and edits stopped reaching the file.
- The shelf looks a document up by identifier and ignores sidecars that name a file
  outside the shelf.
- Mixed line endings are normalised to the first one found, with a test.
