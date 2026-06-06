# Changelog

All notable changes to Loomings are documented here. Format based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — 2026-06-06

First stable release. The app has been complete enough to use daily for
some time; this version is the line in the sand.

### Install

**macOS (Apple Silicon) — Homebrew:**

```sh
brew install --cask tiagojct/loomings/loomings
```

Homebrew automatically strips `com.apple.quarantine`, so no manual
`xattr` command is needed.

**Direct downloads** are attached below for all platforms (`.dmg`,
`.msi`/`.exe`, `.deb`, `.AppImage`, `.rpm`). For unsigned macOS direct
downloads, after moving the app into `/Applications`:

```sh
xattr -dr com.apple.quarantine /Applications/Loomings.app
```

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

[1.0.0]: https://github.com/tiagojct/loomings/releases/tag/v1.0.0
[0.2.3]: https://github.com/tiagojct/loomings/releases/tag/v0.2.3
[0.2.2]: https://github.com/tiagojct/loomings/releases/tag/v0.2.2
[0.2.1]: https://github.com/tiagojct/loomings/releases/tag/v0.2.1
[0.2.0]: https://github.com/tiagojct/loomings/releases/tag/v0.2.0
