# Changelog

All notable changes to Loomings are documented here. Format based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.1] — 2026-07-14

Web only — no desktop app changes.

### Added

- Basic self-hosted (Umami) page-view analytics on the landing page only
  (`docs/index.html`). The editor app itself is not tracked.

## [1.2.0] — 2026-07-14

Web version, alongside the desktop app. Same editor, same CodeMirror core,
now also runs as a static site with no install.

### Added

- **Web build** at [loomings.tiagojct.eu/app](https://loomings.tiagojct.eu/app)
  — a `platform.js` seam picks a Tauri or browser adapter at runtime, so
  `editor.js` itself is unchanged between the two. Real open/save via the
  File System Access API in Chromium/Edge; other browsers get a file-picker
  open and a download-based save/export. Scratch (crash recovery) and
  recent files persist in IndexedDB. A small toolbar (New/Open/Save/
  Export/Theme/About) replaces the native menu, since a browser tab has
  none.
- **Self-hosted deploy**: `Dockerfile`/`nginx.conf`/`docker-compose.yml`
  ship the landing page at the root and the app at `/app` as one static
  site; `docker-publish.yml` publishes a multi-arch image to
  `ghcr.io/tiagojct/loomings` on every release, and a `watchtower`
  sidecar redeploys automatically.

### Changed

- Landing page moved from GitHub Pages (`tiagojct.eu/loomings`) to
  `loomings.tiagojct.eu`, hosted alongside the app. The desktop app's
  About panel and Help → Website menu item point here now too.
- Desktop release CI dropped the Intel Mac (`macos-13`) target — its
  free-tier runner queue was consistently too long to land with the rest
  of a release. Intel Mac users build from source.

## [1.1.0] — 2026-07-13

Performance release plus two new theme families. Typing is now free of
per-keystroke full-document work, file writes are atomic, and the theme
menu grows Glauca and Try-Works alongside Pequod.

### Added

- **Two new theme families**: **Glauca** (Profundum dark / Pruina light,
  the glaucous bloom) and **Try-Works** (Try-Fire dark / True Lamp light,
  Moby-Dick ch. 96), ported from their design-system source tokens.
  Pick the family in View → Theme; ⌘⇧T still cycles system/light/dark
  within the family. Persisted across launches.
- **Typewriter scrolling** (View menu) — keeps the cursor line vertically
  centered while typing, and while moving the cursor with arrows/clicks.
- **Reading time** (`~N min`, 200 wpm) in the stats bar, and **selection
  stats**: while text is selected the stats bar shows the selection's
  words/chars/lines.
- **Export HTML** (File menu) — standalone HTML file rendered with the
  current theme's palette, via the same sanitized renderer as Preview.
- **Drag-and-drop to open** — drop a markdown file onto the window.

### Performance

- **No more per-keystroke O(document) work.** Word-count and preview
  renders were recomputed on every keystroke (even with the stats bar
  hidden); both are now debounced and skipped when their UI is hidden.
  Word counting itself no longer allocates a full split() array.
- **Focus-mode decorations** rebuilt on every view update (including
  scrolls) even when focus mode was off; now rebuilt only on edits,
  cursor moves, or mode toggle.
- Removed a dead `highlightActiveLine` extension (styled invisible but
  running on every update).
- **Scratch autosaves skip unchanged content** and moved off the IPC
  fast path (`spawn_blocking`), as did file saves.
- **Recents menu updates no longer rebuild the entire menubar** — only
  the Open Recent submenu's items are swapped.

### Fixed

- **App icon size.** The macOS icon was noticeably larger than sibling app
  icons in the Dock/Launchpad — its content filled more of the canvas than
  Apple's own icons do. Measured System Settings/Notes/Mail/Safari's actual
  `.icns` files pixel-by-pixel and matched the icon build to the same ratio.
- **Atomic file writes.** Saves, scratch, and the recents list now write
  temp-file-then-rename — a crash mid-write can no longer truncate the
  document being saved.
- **Concurrent-save races.** An autosave and an explicit ⌘S (or two saves
  landing close together) could overlap on the same temp file and corrupt
  or drop one of the writes; saves and scratch writes now serialize.
- **A slow save could stomp fresher state.** If a save was still in flight
  when the buffer moved on (New, Open, external reload, Save As), its
  late-arriving result could overwrite the newer buffer's save/scratch
  bookkeeping — including resurrecting a crash-recovery draft for a file
  the user had already switched away from. Saves now check whether the
  buffer they were writing for is still current before applying results.
- **Crash-recovery draft could resurface for already-discarded content**
  when opening a different file, reloading from disk, or after Save As —
  not just after a plain autosave (fixed above). All of these now clear
  the stale draft.
- **Cold-launch file-open race fully closed.** A macOS "Open With" file
  could still be dropped if it arrived in the narrow window between the
  app finishing startup and the frontend's ready handshake; the two were
  tracked independently and could race across threads.
- **"Open Example" no longer opens the bundle resource as an editable
  file** — autosave could write into the app bundle (or fail on
  read-only installs). The example now opens as an untitled buffer.
- **Line Numbers setting stuck on.** A string/boolean mix-up made the
  persisted setting truthy regardless of value, re-enabling line numbers
  on every launch.
- **Spurious "File changed on disk" prompt while typing.** The file
  watcher could echo Loomings' own autosave (buffer had newer keystrokes
  than disk); accepting the reload silently discarded them. Own-write
  echoes are now recognized and ignored.
- **Closing a named file no longer threatens data loss.** ⌘W during the
  2-second autosave window flushes the pending save instead of showing a
  misleading "unsaved changes will be lost" prompt (untitled buffers
  still prompt).
- **External links** (About, update banner, Help menu, Preview) now open
  through the opener plugin — `window.open` in a Tauri webview is not
  guaranteed to reach the system browser.
- **Window title extension stripping** now covers `.markdown`, `.qmd`,
  `.rmd`, `.txt` (was `.md` only).
- **⌘I on `**bold**`** no longer mangles it into `*bold*`, and repeated
  ⌘I presses toggle italic on/off cleanly instead of piling up asterisks.
- **⌘⇧ shortcuts work with caps lock on.**
- **App version single-sourced** — the About dialog reads the version
  from Tauri instead of a hard-coded string (which had already drifted
  once).
- Scratch recovery no longer prompts when the crashed session's buffer
  matches the file already on disk, and steady-state typing no longer
  deletes/recreates the scratch file every autosave cycle.

## [1.0.3] — 2026-06-15

Internals patch from the launch-readiness audit (Tier 2). No new features
in the editor itself; what changes here is correctness, security, and one
small View-menu addition.

### Added

- **Line numbers toggle** in View menu. Persisted across launches.
- **Strict-ish Content Security Policy.** The shipped build now restricts
  resource loading to `self`, the Tauri IPC scheme, and `api.github.com`
  for the update check. Previously the policy was disabled entirely.
- **Unit tests for the update-check version parser.** Covers `v`-prefix
  stripping, pre-release suffixes (`-rc.1`, `-beta`), build metadata
  (`+build.42`), and rejects malformed input.

### Fixed

- **Close-window race condition.** The previous double-tap-close guard
  kept its state in a Rust-side mutex with a 2-second window. A second
  close request landing in that window was force-accepted regardless of
  the unsaved-confirm result. The state machine is gone — Rust now
  unconditionally intercepts every close request and waits for an
  explicit `confirm_quit` from the frontend before exiting.
- **Cold-launch race between Apple Events and the JS event listener.**
  When opening Loomings by double-clicking a `.md` file from Finder on
  the very first launch, the file path could arrive before the renderer
  had attached its `file-opened` listener, dropping the file silently.
  The path is now cached on the Rust side and drained by the JS init
  flow once listeners are ready. Warm-launch "Open With" while the app
  is already running takes the direct emit path as before.
- **Tokio worker starvation during update check.** The synchronous
  `ureq` GET to GitHub Releases ran on a tokio worker thread, blocking
  it for up to 5 seconds and starving every other IPC command. The
  call now runs on `tauri::async_runtime::spawn_blocking` so the worker
  thread stays free for IPC during the network round-trip.
- **Silent file-watcher failures.** If the OS denied the watch
  registration (sandbox, network filesystem, missing capability), the
  failure was swallowed and external-edit detection was quietly dead.
  Failures now flash in the statusbar.

## [1.0.2] — 2026-06-09

Polish patch from the launch-readiness audit.

### Added

- **Browser-native spellcheck** in the editor. Misspelled words underline
  while you type, right-click for the system dictionary suggestions, all
  via WebKit / WebView2 / WebKitGTK.
- **First-launch welcome modal** with per-OS instructions for setting
  Loomings as the default `.md` handler. Dismissable, shown once.
- **`og:site_name` and `og:locale`** meta tags so social previews on
  Slack, LinkedIn, iMessage display the site name beside the OG card.

### Changed

- **Update check shows "Checking for updates…" in the statusbar**
  when triggered from Help → Check for Updates. Previously the manual
  check returned silently if nothing was found until the result toast.
- **Intel macOS download removed from the landing page and README.**
  The free-tier `macos-13` runner queue means the Intel `.dmg` has not
  shipped in the v1.0.x line; advertising it was a broken promise.
  Intel users are now pointed at building from source.
- **Instagram launch script is committed; generated PNGs are
  gitignored.** The script (`social/instagram/generate_images.py`) is
  the source of truth; the images regenerate from it. Cuts ~30 MB
  from the repo working tree.

## [1.0.1] — 2026-06-08

### Added

- **File associations on all three platforms.** Loomings now registers
  itself as a handler for `.md`, `.markdown`, `.mdown`, `.mkd`, `.qmd`,
  `.rmd`, and `.txt`. After installing this version you can right-click
  a markdown file in Finder/Explorer/your file manager and pick
  "Always Open With Loomings" — double-click then opens the file in
  Loomings directly. Files passed on launch (via Finder double-click,
  `open file.md`, or argv) are loaded on startup.

### Fixed

- **Close-cancel bypass that could lose unsaved work.** When the quit
  confirmation prompt was declined and a second close attempt arrived
  within two seconds, the window was force-closed regardless. The
  client now resets the close-tracker on cancel, so the prompt is
  shown again on the next attempt.
- **File-watcher registration race.** Three callers (loading a file,
  save-as, scratch recovery) were fire-and-forget against the OS
  watcher. An external edit landing in the few-ms gap was silently
  missed. All three now await the registration before continuing.
- **Social-card preview on LinkedIn, X, Slack, iMessage.** The
  Open Graph and Twitter image meta tags pointed at a relative path.
  Social crawlers require absolute URLs; they were silently falling
  back to no preview. Now both point at the full
  `https://tiagojct.eu/loomings/assets/og.png`. An `og:url` canonical
  was added at the same time, and the meta `description` was brought
  into line with `og:description` (Oxford comma).

## [1.0.0] — 2026-06-06

First stable release. The app has been complete enough to use daily for
some time; this version is the line in the sand.

### Install

**macOS (Apple Silicon) — Homebrew:**

```sh
brew install --cask --no-quarantine tiagojct/loomings/loomings
```

The `--no-quarantine` flag is required because the build is unsigned.
Modern Homebrew adds the `com.apple.quarantine` xattr by default; without
the flag, Sequoia and Tahoe Gatekeeper refuse to launch the app with
*"Loomings.app is damaged."* If you have already installed without the
flag, fix the existing copy with:

```sh
xattr -dr com.apple.quarantine /Applications/Loomings.app
```

**Direct downloads** are attached below for all platforms (`.dmg`,
`.msi`/`.exe`, `.deb`, `.AppImage`, `.rpm`). For unsigned macOS direct
downloads, run the same `xattr` command after moving the app into
`/Applications`.

### Editor
- Real markdown syntax in the editor — bold, italic, headings (H1/H2/H3/H4
  visually distinct), inline code, links.
- Markdown shortcuts: ⌘B / ⌘I wrap selection, ⌘\` for code, ⌘K for link.
  Toggle-aware: pressing again unwraps.
- Smart list auto-continue: `-`, `*`, `+`, `1.`, and `>` extend on Enter;
  pressing Enter on an empty list item exits the list.
- Smart typography: straight quotes → curly, `--` → em-dash, `...` →
  ellipsis. Toggle in View menu.
- YAML frontmatter detection — `---` blocks at document start render dimmed.
- Native undo, IME, paste-as-plaintext, scroll, selection (CodeMirror 6).

### Navigation
- Outline palette (⌘P) — fuzzy-jump to any heading with ↑↓ Enter Esc.
- Find/Replace (⌘F) — CodeMirror search panel with regex, case sensitivity,
  replace.
- Recent files menu (File → Open Recent), last 10 files persisted.
- Cursor position (`Ln 5, Col 12`) in statusbar.
- Now opens `.qmd` and `.rmd` files alongside `.md`, `.markdown`, and `.txt`.

### Writing flow
- Focus mode (⌘⇧D) — dims everything outside the *current sentence* (not
  just the paragraph).
- Preview (⌘⇧P) — full markdown-it rendering with sanitized URLs.
- Word goal (⌘⇧G) — 7 presets cycle: off → 250 → 500 → 750 → 1000 → 2000 →
  5000. Progress shows in the statusbar.
- Column-width cycle (⌘⇧W) — wide (900px) / normal (660px) / narrow (500px).

### Themes
- Pequod navy (dark) + Pequod parchment (light) + system-follow mode.
- Cycle theme (⌘⇧T). All surfaces share the same palette: editor, syntax
  highlighting, preview, modals, statusbar, titlebar.

### Files
- Auto-save 2 seconds after last edit, for named files.
- Crash-recovery scratch buffer — last buffer restored on next launch.
- External file watcher (`notify-debouncer-mini`) — prompts reload if the
  current file changes on disk.
- Double-tap-close guard: requires two close attempts within 2 seconds to
  prevent accidental data loss.

### App
- About modal (Help menu) and a populated macOS native About panel with
  name, version, MIT license, website, copyright.
- Open Example (Help menu) — opens the bundled chapter 1 of *Moby-Dick*,
  the chapter the app is named for.
- Update check — checks GitHub Releases on launch and on demand (Help →
  Check for Updates). Notification-only; downloads stay on the releases
  page. Avoids breaking unsigned builds with mid-install quarantine.

### Builds
- 4-platform CI on tag push: macOS arm64, macOS x64, Linux x64, Windows x64.
- Bundle outputs: `.dmg` (macOS), `.exe` + `.msi` (Windows), `.deb` +
  `.AppImage` + `.rpm` (Linux).
- Releases attach all platform installers to a single tagged release.

## [0.2.3] — 2026-05-27

### Added
- About Loomings modal + populated macOS About panel (`AboutMetadataBuilder`).
- Bundled example: chapter 1 of *Moby-Dick* as a Tauri resource. Help →
  Open Example loads it.
- Update check via `ureq` against the GitHub Releases API; notification
  banner appears for newer versions.
- Help menu: About, Open Example, Check for Updates, Visit Website, GitHub.

### Changed
- File-dialog filters were too narrow (will be widened further in 1.0.0).

### Fixed
- Multi-platform release pipeline now attaches assets to the correct tagged
  release instead of creating per-job untagged drafts.

## [0.2.2] — 2026-05-26

### Added
- Multi-platform builds via GitHub Actions: macOS arm64 + x64, Linux x64,
  Windows x64.
- Windows `icon.ico` and `bundle.targets: "all"` to actually produce per-
  platform installers.

### Changed
- Release workflow uses `tag_name: ${{ github.ref_name }}` so all matrix
  jobs attach assets to the same release.

## [0.2.1] — 2026-05-26

### Added
- README + landing page document the `xattr -dr com.apple.quarantine`
  workaround for unsigned macOS builds, since right-click → Open is
  blocked on Sequoia and Tahoe.

### Changed
- Release workflow extended to Windows and Linux runners (initial cut).

## [0.2.0] — 2026-05-26

Initial public release of the Tauri 2 + CodeMirror 6 rewrite. Replaces the
earlier Electron prototype.

### Added
- Inline markdown syntax highlighting.
- Focus mode dimming non-current sentence.
- Outline palette (⌘P).
- Smart typography.
- Word goal.
- External file watcher.
- Crash recovery via scratch buffer.
- Dark + light Pequod themes following system preference.

[1.0.3]: https://github.com/tiagojct/loomings/releases/tag/v1.0.3
[1.0.2]: https://github.com/tiagojct/loomings/releases/tag/v1.0.2
[1.0.1]: https://github.com/tiagojct/loomings/releases/tag/v1.0.1
[1.0.0]: https://github.com/tiagojct/loomings/releases/tag/v1.0.0
[0.2.3]: https://github.com/tiagojct/loomings/releases/tag/v0.2.3
[0.2.2]: https://github.com/tiagojct/loomings/releases/tag/v0.2.2
[0.2.1]: https://github.com/tiagojct/loomings/releases/tag/v0.2.1
[0.2.0]: https://github.com/tiagojct/loomings/releases/tag/v0.2.0
