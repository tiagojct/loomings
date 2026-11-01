# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Loomings is a browser-only Markdown editor for writing, sharing with
students and teaching Markdown side by side. Plain JS, Vite, CodeMirror 6,
markdown-it. No framework, no backend: a static site (`docs/` landing page
at the root, the app at `/app`) deployed via Docker/nginx at
loomings.tiagojacinto.eu (VPS: /opt/vps/apps/loomings, Caddy + Cloudflare Tunnel). The Tauri
desktop app (1.x) was retired; it lives on the `desktop-final` branch.

- `src/editor.js` (~1700 lines) — the editor: CodeMirror setup, in-place
  Markdown rendering (`makeHighlight`/`makeTheme` from a palette), view
  modes and scroll sync, preview, menus, share links, lessons, documents,
  keyboard shortcuts, boot sequence. Imports browser APIs only through
  `browser.js`.
- `src/session.js` — the document session: dirty flag, scratch debounce,
  draft write ordering, document generation, save serialisation, and the
  containment of every storage failure. Headless; `editor.js` injects the
  text, the home and the writes. 11 tests in `session.test.js`.
- `src/browser.js` — everything that touches the browser: File System
  Access API with picker/download fallback, IndexedDB (scratch, recents,
  documents), `document.title`, `window.confirm`, launch queue, service
  worker registration.
- `src/modal.js` — the dialog contract (inert background, Tab wrap, Escape,
  focus restore). `src/html.js` — `escapeHtml`, safe in attribute context.
- `src/fonts.css` — the self-hosted `@font-face` rules; files and licences
  live in `public/fonts/`.
- `src/palettes.js` — the ten Ensigns colour families. The only place a colour
  lives; `editor.js` writes them onto `<html>` as CSS variables and
  `style.css` reads those (it keeps only a Pequod pre-script fallback).
- `src/share.js` — document ⇄ URL fragment. Pure, tested.
- `src/lessons.js` — index of `lessons/NN-slug.md` via `import.meta.glob`.
- `src/sw-template.js` + the plugin in `vite.config.js` — the service worker,
  emitted as `sw.js` with the build's asset list.

## Native macOS app (Stages 1–6)

`macos/` is a separate SwiftPM app for Apple Silicon on macOS 15+. It does
not replace or import the web app, and native-only work must not change web
release numbers.

- `Sources/LoomingsMarkdown` — cmark-gfm parsing plus the UTF-8→UTF-16
  source map. `MarkdownTree` reads cmark's own nodes in place; swift-markdown
  was dropped because copying every node into its Swift tree was about 85% of
  a parse. Options match swift-markdown's defaults (smart punctuation,
  source positions, table spans; table, strikethrough and tasklist). cmark
  reports 1-based byte columns; AppKit ranges are UTF-16, so every parser
  range goes through `SourceMap`. The parse output also
  carries the outline (ATX and setext), frontmatter range, line starts and a
  word count (`TextStatistics`, mirroring `src/stats.js`).
- `Sources/LoomingsTheme` — decodes the exported Ensigns palettes, resolves
  System/Light/Dark, and provides `NSColor`/contrast helpers. The editor,
  preview and HTML export all take colours from this one model.
- `Sources/LoomingsShare` + `Sources/CZlib` — raw DEFLATE (RFC 1951) through
  zlib for the web share format. `#d=p.` (raw UTF-8) and `#d=z.` are both
  decoded; links are capped at 4 MB encoded and 8 MB decoded. Links are
  generated on `loomings.tiagojacinto.eu/app/` and can carry `theme`/`mode`.
- `Sources/LoomingsPreview` — a native renderer for the preview and export.
  It walks the cmark tree once per render and produces per-block
  attributed text plus HTML. Source lines/ranges ride on the blocks for
  split-view sync; the HTML mirrors markdown-it (`data-line`, linkify,
  typographer, sanitised URLs, raw HTML escaped, frontmatter omitted). Tables
  use `NSTextTable`; images become `NSTextAttachment` placeholders with a
  sanitised source for the view to load asynchronously.
- `Sources/LoomingsEditor` — `EditorController` owns the TextKit 2
  `NSTextView`. `textDidChange` only bumps a revision and schedules a
  debounced background parse; results apply only when their revision is
  still current. Syntax colours are supplied by
  `NSTextLayoutManager.renderingAttributesValidator`, i.e. before a fragment
  is laid out; applying rendering attributes after layout does not repaint
  already-drawn text. Attribute-only changes (spelling) do not advance the
  revision. Editing commands live here too: bold/italic/code/link, list and
  quotation continuation, Tab indent/outdent, smart typography, find bar,
  outline jumps, selection statistics, font size, sentence focus and
  typewriter scrolling.
- `Sources/LoomingsDocuments` — `TextFileCodec` (UTF-8/UTF-16 BOM in and
  out, LF/CRLF/CR preserved, unsupported encodings refused), `LocalShelf`
  (Application Support shelf with UUID filenames, JSON titles and atomic
  writes), and `SaveGeneration`/`FileChangeDetector` (the save-race and
  external-change primitives).
- `Sources/LoomingsApp` — `NSDocument`, window, native toolbar and menus,
  Write/Split/Preview modes, a native preview text view, scroll sync,
  Markdown/HTML/PDF/Print export, the Theme menu, bundled Learn material,
  share commands and About credits.
  A document's home is a user file, a shelf file, or nothing (untitled).
  Shelf documents are ordinary file documents under
  `~/Library/Application Support/Loomings/Shelf/`, so autosave, versions,
  recents and external-change handling all come from NSDocument. File menu:
  Open Recent, Open from Shelf, Import from Browser Export…, Save, Save As…,
  Save to Shelf, Duplicate, Rename…, Browse All Versions…. The window adds a
  status bar (cursor, words, characters, lines, reading time, word goal) and
  a line-number ruler; Format/View/Find menus carry the editing commands and
  preferences. `--self-test` exercises typing, undo/redo, paste, IME,
  revision races, BOM/CRLF round trips, native dirty tracking, autosave, shelf
  saving, the save-generation gate, formatting commands, smart typography,
  focus dimming, the line ruler and typewriter scrolling without a human at
  the keyboard.
- `Sources/LoomingsBench` — Stage 1 measurements (parse, insert call,
  app-owned handler, snapshot, visible-region styling, footprint) over
  10 KB–10 MB corpora.
- `scripts/build-app.sh` — release arm64 `.app` in `macos/dist/`, ad-hoc
  signed (not Developer ID, not notarised).

```sh
./macos/scripts/build-app.sh            # build macos/dist/Loomings.app
macos/dist/Loomings.app/Contents/MacOS/Loomings --self-test
swift test --package-path macos         # Swift Testing; CLT has no XCTest
swift run -c release --package-path macos LoomingsBench

node scripts/export-native-resources.mjs       # palettes + lessons + example
node macos/scripts/render-web-fixtures.mjs     # preview HTML fixtures
node macos/scripts/render-share-fixtures.mjs   # cross-language share fixtures
```

Stage 2 decisions worth preserving:

- Saves are forced onto the main thread (`canAsynchronouslyWrite` is false)
  because the text is main-actor state; do not make writes asynchronous
  without first snapshotting text and data off the editor.
- `data(ofType:)` captures the editor's edit generation; a save completion
  records it through `SaveGeneration`, and an older completion is ignored.
  The self-test proves edits made during a save stay edited.
- Every document is read into LF-normalised text. The original encoding,
  BOM and line ending are stored and restored on write.
- External changes are checked on app activation: unedited documents reload,
  edited ones get a Keep/Reload sheet. Deleted files get a Keep/Close sheet.
- The shelf replaces the browser shelf. It has no automatic migration from
  IndexedDB; `Import from Browser Export…` copies exported Markdown files.
- Focus mode stores its dim/label colours in the text storage while active
  and removes them when switched off. Rendering attributes cannot recolour
  text that is already laid out, so the transient override is deliberate;
  focus does not dirty the document (the self-test checks this).
- Line numbers draw from TextKit line fragments and the parser's line starts,
  so wrapping, font size and column width stay aligned. Stats use the
  background parse snapshot; selection stats are computed on demand.
- Preview rendering runs on its own serial queue with a generation token; a
  stale render is dropped and typing never waits for it. The preview view
  replaces only the changed block ranges and restores its top source line
  across content, image-load and resize changes.
- The preview is TextKit 1 (not the editor's TextKit 2) so `NSTextTable`,
  attachment cells and the classic layout APIs are available. It is a
  separate surface; do not move syntax rendering into it.
- The Theme menu applies the selected Ensigns family to editor syntax,
  preview, line numbers and HTML export; native controls follow
  `NSApp.appearance`. The ten palettes are generated from `src/palettes.js`:
  `node scripts/export-native-resources.mjs`. Do not hand-edit
  `macos/Resources/palettes.json`.
- Editor base text colour lives in the text storage (uniform foreground),
  because NSTextView's `textColor` is not reliable for TextKit 2 across a
  string replacement. Syntax markers remain rendering attributes; focus and
  frontmatter override the storage colour and restore it.
- Fonts are native TTF files in `macos/Resources/Fonts` (JetBrains Mono and
  Source Serif 4, both OFL with licence files). `ATSApplicationFontsPath`
  registers them at launch. Do not add WOFF2 loading.
- The native icon is separate from the web/social icons. Run
  `swift macos/scripts/build-icon.swift` to redraw the Adamastor-style padded
  squircle (830/1024 optical), cream keyline and flat L into
  `macos/Resources/AppIcon.icns`; `build-app.sh` copies that. Do not feed
  `icons/rendered` or the Icon Composer export to the native bundle: they are
  full-bleed and glassy.
- Share fixtures are generated with `node macos/scripts/render-share-fixtures.mjs`;
  the Swift tests decode those and also run the web decoder through Node, so
  both directions are exercised. No custom URL scheme or universal link is
  registered: opening an https URL stays in the browser unless the user picks
  File → Share → Open Share Link.
- HTML fixtures live in
  `macos/Tests/LoomingsPreviewTests/Fixtures` and are generated from the web
  renderer with `node macos/scripts/render-web-fixtures.mjs`;
  `PreviewHTMLTests` compares the output byte for byte.
- `macos/ACCEPTANCE.md` is the Stage 6 checklist, themed measurements, data-replacement
  test and the explicit list of untested environments and performance misses. Read it
  before claiming parity or performance.
- Preview rendering is whole-document per update with a per-block cache.
  Release p95 (`LoomingsBench --preview`): a one-block edit is 4.4 ms at
  100 KB and 52 ms at 1 MB; a cold render 38 ms and 398 ms. The live
  preview renderer is `PreviewRenderer(producesHTML: false)`; export builds a
  fresh renderer with HTML. Keep the Typographer/Linkifier fast paths exact:
  a test checks they skip only text that cannot change.
- `Loomings --snapshot <dir> <file.md>` writes write/split/preview PNGs of the
  real window without screen-recording access. Override preferences for one
  run with argument defaults, e.g. `-Loomings.Native.themeFamily pequod
  -Loomings.Native.themeMode dark`. Use it for design review.
- Window chrome, status bar, split divider and scrollers take the palette:
  the title bar is transparent over the document ground. The preview keeps a
  reading measure of 0.9 x the column width. With line numbers on, the ruler
  takes the whole left margin so the numbers sit next to the centred column.
- Title bar (`ToolbarControls.swift`): a custom `ModeSwitch` (Write/Split/
  Preview) centred with `centeredItemIdentifiers`, then Outline, Theme and
  Copy Share Link as `ToolbarIconButton`s: one symbol size and weight in
  equal 28 pt cells, so the row lines up whatever each glyph's shape. New,
  Open and Save were removed from the bar; they stay in the File menu. The
  window minimum is 640 pt wide so nothing overflows into the chevron.
  `ThemedScroller` paints legacy scroller tracks with the document ground.
- Preview code blocks and tables are framed `NSTextBlock`s. Each code line is
  its own paragraph, so space around a frame comes from an empty spacer
  paragraph after it (`blockSpacer`), not from paragraph spacing (it lands
  inside the frame) or block margins (they take the fill). Quotes use the
  bundled Source Serif 4 italic; strong text inside them falls back to bold
  roman because no bold italic is bundled.
- Native shortcuts that collide with macOS conventions were deliberately not
  kept: Column Width and Word Goal have no key equivalent (⇧⌘W is Close All,
  ⇧⌘G is Find Previous).

Appearance, teaching material and share links are in place. Stage 6 remains:
personal installation, the complete parity checklist against web release
2.3.0, accessibility/performance retesting, and honest reporting of the
preview render budget.

## Commands

```sh
npm install
npm run dev        # Vite dev server, http://127.0.0.1:1420/app/ (no service worker in dev)
npm test           # Vitest (src/**/*.test.js)
npm run typecheck  # tsc over src/, checkJs + strictNullChecks + unused locals
npm run build      # dist/ — app at /app/, sw.js, manifest, icons, fonts
npm run preview    # serves dist/ at http://127.0.0.1:4173/app/ (service worker active)
```

`.claude/launch.json` has `loomings-dev` and `loomings-preview` for the
browser pane.

## Conventions that matter

- **`base` is `/app/`** in `vite.config.js`, and must match `nginx.conf`'s
  `/app` mount, the manifest's `scope`/`start_url`, and the service
  worker's `BASE`. Change them together.
- **Colours only in `palettes.js`, and only from Ensigns.** The ten families
  are Ensigns roles (ensigns.tiagojacinto.eu) mapped once: bg, bgElev,
  bgDeep, fg, fgDim, fgGhost, accent, accentLight (the link role),
  accentDim, border, selection, onAccent. Add a family there (dark + light,
  the twelve `PALETTE_KEYS`, optional ink roles `heading`/`emphasis`/`code`/
  `marker`) and to `FAMILY_ORDER`; the theme menu, CodeMirror themes, CSS
  variables and HTML export all follow. `npm test` enforces WCAG floors per
  mode, plus text-on-accent and a visible selection. Do not introduce a hex
  that is not an Ensigns role.
- **The document's home is one of three:** a file handle (`currentFile`,
  handle kept in `browser.js`), a browser document (`currentDocId`,
  IndexedDB), or nothing (untitled). `writeToHome` (`editor.js`) dispatches
  on that; `handleSave` picks a home for untitled buffers (file picker where
  the File System Access API exists, otherwise the browser). `loadFile`
  resets both and calls `forgetFile()` for content with no file behind it.
- **Don't hand-roll save or scratch timing in `editor.js`.** It calls
  `session.markEdited()` / `saveNow()` / `discardScratch()` / `adopt()` /
  `repoint()` and the module owns the timers, the ordering and the error
  containment. Every storage call it makes is caught: nothing may surface as
  an unhandled rejection, because `fileNew`/`loadFile` await the same chain.
- **Dialogs go through `openModal`** (`src/modal.js`), which makes the page
  behind inert, wraps Tab, closes on Escape and restores focus to the
  opener. `.hidden` is still what hides them.
- **Boot order** (bottom of `editor.js`): launch queue consumer, then a
  document named in the URL (`#d=` share payload or `?lesson=`), which
  wins over scratch recovery and is stripped from the URL, then scratch
  recovery. Don't reorder.
- **Scratch** is written to IndexedDB ~0.8s after edits and cleared when
  the buffer is saved, replaced, or recovery is declined. A surviving
  scratch on the next visit means an unsaved draft.
- **Preview sanitizes URLs** by overriding markdown-it's `link_open` and
  `image` rules, and stamps `data-line` on block tokens for scroll sync.
  Preserve both when touching the renderer.
- **Toolbar menus** use `attachMenu(btn, menuEl, {onOpen, onPick})`; items
  are `.tb-menu-item` buttons with `data-*` attributes. Menus in the
  right-hand group carry `.tb-menu-right`.
- **`history` is shadowed** in `editor.js` by CodeMirror's `history()`
  import. Use `window.history`.
- **CSP is strict** (`nginx.conf`). The app makes no network requests
  beyond its own origin; keep it that way.
- **nginx never sees TLS.** Cloudflare and Caddy terminate it, so any
  absolute redirect nginx builds says `http://`. `absolute_redirect off`
  keeps redirects relative; link to `/app/` with the slash.
- **CDN cache:** Cloudflare fronts the site and cannot be purged with the
  VPS's token (`purge_cache` fails with an auth error — it's DNS-scoped
  only), and it caches by file extension at the edge even for files nginx
  sends no explicit `Cache-Control` for. nginx's own 1-year immutable rule
  in `nginx.conf` is scoped to `/app/assets/` (Vite's hashed output)
  precisely because it once also matched the landing page's unhashed
  `docs/style.css` and pinned a stale copy for a year (2026-09-21). Any
  unhashed file under `docs/` that changes — `style.css`, `screenshot.png`,
  `og.png` — is referenced from `docs/index.html` with a `?v=<version>`
  query string, the same trick `sw.js` uses, so a new release is always a
  new URL rather than a bet on cache headers. Bump those query strings
  whenever the file changes, not just the version number.
- **Version** lives in `package.json` only. The service worker's cache
  name and the About dialog read it from there.
- **The landing page (`docs/`)** is a separate surface from the app: its own
  stylesheet, its own `landing.js` (the source/result pairing), and its faces
  loaded from `/app/fonts/`. Its unhashed files are cache-busted by `?v=` in
  `docs/index.html`; bump them when the file changes, not only on a release.
- **Fonts are self-hosted** (`public/fonts/`, latin woff2) because the CSP
  is self-only. The service worker precaches every public file with an
  asset extension (woff2/png/svg/webmanifest/ico), so a new font, icon or
  manifest is picked up automatically; nginx serves
  `/app/fonts/` with a one-day cache (not the year-long immutable rule,
  which only covers hashed `/app/assets/`). A changed face should get a new
  filename rather than rely on cache headers.
- **`theme-color` is set from the palette at runtime** (`applyThemeAttr`);
  the `<meta>` in `index.html` and the manifest's `theme_color` stay Pequod
  as the pre-script default and cannot follow the family.
- **`npm run typecheck` is a gate**, not decoration: `checkJs` with
  `strictNullChecks` already caught a live `ReferenceError` (Escape) and the
  `tx.transaction?.error` typo. Keep it green.
- Lessons are plain Markdown without raw HTML (the preview has
  `html: false`); the lessons test enforces it.
