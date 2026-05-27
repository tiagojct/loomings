# Loomings

A markdown writing app for macOS, Windows, and Linux. The shapes loom before they take form.

Built with Tauri 2 + CodeMirror 6. ~12 MB binary, native system WebView, Rust backend.

**Site:** [tiagojct.eu/loomings](https://tiagojct.eu/loomings)
**Downloads:** [Latest release](https://github.com/tiagojct/loomings/releases/latest)

## Install

| Platform | File |
|---|---|
| macOS (Apple Silicon) | `Loomings_<ver>_aarch64.dmg` |
| macOS (Intel) | `Loomings_<ver>_x64.dmg` |
| Windows | `Loomings_<ver>_x64-setup.exe` or `_x64_en-US.msi` |
| Linux (Debian/Ubuntu) | `Loomings_<ver>_amd64.deb` |
| Linux (other) | `Loomings_<ver>_amd64.AppImage` |
| Linux (Fedora/RHEL) | `Loomings-<ver>-1.x86_64.rpm` |

### macOS Gatekeeper

App is unsigned (no Apple Developer ID, $99/yr). macOS Sequoia/Tahoe blocks "right-click → Open" for unsigned apps. After moving `Loomings.app` to `/Applications`, strip the quarantine attribute:

```sh
xattr -dr com.apple.quarantine /Applications/Loomings.app
```

App opens normally after that. Alternative: open System Settings → Privacy & Security, attempt to launch, then click "Open Anyway".

## Features

### Editor
- Real markdown syntax in the editor — bold reads bold, headings read as headings (H1/H2/H3/H4 sized), code reads code, links underline.
- Markdown shortcuts: **⌘B / ⌘I** wrap, **⌘\`** code, **⌘K** link.
- Smart list auto-continue: `- `, `* `, `+ `, `1. `, `> ` extend on Enter; double-Enter exits.
- Smart typography: straight quotes → curly, `--` → em-dash, `...` → ellipsis. Toggle in View menu.
- YAML frontmatter detection (`---\n…\n---` at top is dimmed).
- Native undo, IME, paste-as-plaintext, scroll, selection (CodeMirror 6).

### Navigation
- **Outline palette** (⌘P) — fuzzy-jump to any heading.
- **Find/Replace** (⌘F) — CodeMirror panel with regex, case, replace.
- **Recent files** menu (File → Open Recent).
- Cursor position (`Ln 5, Col 12`) in statusbar.

### Writing flow
- **Focus mode** (⌘⇧D) — dims everything outside the current sentence.
- **Preview** (⌘⇧P) — full markdown-it rendering with sanitized URLs.
- **Word goal** (⌘⇧G) — set target, progress shows in statusbar.
- Column-width cycle (⌘⇧W) — wide / normal / narrow.

### Themes
- Pequod navy (dark) + Pequod parchment (light) + system-follow.
- Cycle theme (⌘⇧T).

### Files
- **Auto-save** 2s after last edit, for named files.
- **Crash-recovery** scratch buffer — last buffer restored on next launch.
- **External file watcher** — prompts reload if file changes on disk.

### App
- **About modal** + populated macOS About panel (Help menu).
- **Open Example** (Help menu) — chapter 1 of Moby-Dick, the namesake of the app.
- **Update check** — banner appears if a newer release is published; links to GitHub. No auto-install (unsigned builds can't survive macOS quarantine).

## Build from source

Prerequisites: Xcode Command Line Tools (macOS) or build-essential (Linux) or Visual Studio Build Tools (Windows), Rust, Node 20+.

```sh
git clone https://github.com/tiagojct/loomings
cd loomings
npm install
npm run dev          # dev with hot reload
npm run build        # produces installer in src-tauri/target/release/bundle/
```

Linux additionally needs:
```sh
sudo apt install libwebkit2gtk-4.1-dev libgtk-3-dev libayatana-appindicator3-dev librsvg2-dev patchelf
```

First Rust compile: 3-5 min. Subsequent builds: seconds.

## Keyboard shortcuts

| Action | Shortcut |
|---|---|
| New | ⌘N |
| Open | ⌘O |
| Open Recent | File menu |
| Open Example (Moby-Dick chapter) | Help menu |
| Save / Save As | ⌘S / ⌘⇧S |
| Close Window / Quit | ⌘W / ⌘Q |
| Bold / Italic / Code / Link | ⌘B / ⌘I / ⌘\` / ⌘K |
| Find | ⌘F |
| Jump to Heading | ⌘P |
| Focus Mode | ⌘⇧D |
| Preview | ⌘⇧P |
| Stats | ⌘⇧L |
| Cycle Column Width | ⌘⇧W |
| Cycle Theme | ⌘⇧T |
| Cycle Word Goal | ⌘⇧G |
| Font Size +/- | ⌘= / ⌘- |
| Fullscreen | F11 |
| DevTools | ⌘⌥I |

(⌘ = Cmd on macOS, Ctrl on Windows/Linux.)

## Project layout

```
loomings/
  src/                    # frontend (Vite + CodeMirror 6 + markdown-it)
    editor.js             # everything: editor, menu listeners, IPC
    index.html
    style.css
    icon.png              # served via Vite at runtime (About modal)
  src-tauri/              # Rust backend (Tauri v2)
    src/lib.rs            # IPC commands, menu, file watcher, update check
    capabilities/         # Tauri permission allowlist
    icons/                # ICNS, ICO, sized PNGs
    tauri.conf.json
    Cargo.toml
  examples/loomings.md    # Moby-Dick chapter 1 (bundled as resource)
  icons/                  # Icon Composer .icon bundle + exports
  scripts/                # icon build pipeline (Swift + sips)
  docs/                   # landing page (tiagojct.eu/loomings)
  .github/workflows/      # 4-platform release automation
```

## Stack

- **Tauri 2** — Rust shell + system WebView (WKWebView / WebView2 / WebKitGTK). No bundled Chromium.
- **Vite 5** — frontend bundler.
- **CodeMirror 6** — editor with lezer markdown grammar + syntax highlighting + search + history.
- **markdown-it 14** — preview renderer with linkify + typographer.
- **notify** (Rust) — external file watcher.
- **ureq** (Rust) — sync HTTP client for the update check.

## License

MIT — see [LICENSE](LICENSE).

Chapter 1 of *Moby-Dick* (bundled at `examples/loomings.md`) is public domain.
