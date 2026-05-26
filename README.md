# Loomings

A minimalist Markdown writing app. The shapes loom before they take form.

Built with Tauri v2 + CodeMirror 6. ~12MB binary, native macOS WebKit, Rust backend.

**Site:** [tiagojct.eu/loomings](https://tiagojct.eu/loomings)

## Features

- Real Markdown syntax highlighting in source view (bold, italic, headings, code, links)
- Markdown shortcuts: Cmd+B / Cmd+I / Cmd+K / Cmd+`
- Smart list auto-continue (`- `, `1.`, `> `) + Enter to exit list
- Smart typography (`"foo"` → `“foo”`, `--` → `—`, `...` → `…`)
- Heading hierarchy (H1/H2/H3 visually distinct)
- Outline palette (Cmd+P) — jump to any heading
- Focus mode — dims everything outside current sentence (Cmd+Shift+D)
- YAML frontmatter detection
- Pequod theme (dark) + Pequod parchment (light) + system-following mode
- Word goal + progress (Cmd+Shift+G)
- Cursor position in statusbar
- Find/Replace (Cmd+F) via CodeMirror search
- Live Markdown preview (Cmd+Shift+P)
- External file change watcher — prompts reload when file changes on disk
- Auto-save (2s after edit) for named files
- Crash-recovery scratch buffer
- Recent files menu

## Install

Download the latest installer from [Releases](https://github.com/tiagojct/loomings/releases):

- **macOS**: `Loomings_*_aarch64.dmg` (Apple Silicon) or `Loomings_*_x64.dmg` (Intel)
- **Windows**: `Loomings_*_x64-setup.exe`
- **Linux**: `Loomings_*_amd64.deb` or `.AppImage`

### macOS Gatekeeper

App is unsigned (no Apple Developer ID, $99/yr). macOS Sequoia/Tahoe blocks "right-click → Open" for unsigned apps. After moving `Loomings.app` to `/Applications`, strip the quarantine attribute:

```sh
xattr -dr com.apple.quarantine /Applications/Loomings.app
```

App opens normally after that. Alternative: open System Settings → Privacy & Security, attempt to launch, then click "Open Anyway".

## Build from source

Prerequisites: macOS, Xcode Command Line Tools, Rust, Node 20+.

```sh
xcode-select --install
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
git clone https://github.com/tiagojct/loomings
cd loomings
npm install
npm run dev          # dev with hot reload
npm run build        # production .dmg in src-tauri/target/release/bundle/
```

First Rust compile: 3-5 min. Subsequent builds: seconds.

## Keyboard shortcuts

| Action | Shortcut |
|---|---|
| New | Cmd+N |
| Open | Cmd+O |
| Save / Save As | Cmd+S / Cmd+Shift+S |
| Close Window / Quit | Cmd+W / Cmd+Q |
| Bold / Italic / Code / Link | Cmd+B / Cmd+I / Cmd+` / Cmd+K |
| Find | Cmd+F |
| Jump to Heading | Cmd+P |
| Focus Mode | Cmd+Shift+D |
| Preview | Cmd+Shift+P |
| Stats | Cmd+Shift+L |
| Cycle Column Width | Cmd+Shift+W |
| Cycle Theme | Cmd+Shift+T |
| Cycle Word Goal | Cmd+Shift+G |
| Font Size +/- | Cmd+= / Cmd+- |
| Fullscreen | F11 |
| DevTools | Cmd+Alt+I |

## Project layout

```
loomings/
  src/                  # frontend — Vite + CodeMirror 6 + markdown-it
  src-tauri/            # Rust backend (Tauri v2)
    src/lib.rs          # commands, menu, file watcher
    capabilities/       # Tauri permission allowlist
    icons/              # ICNS + sized PNGs
  icons/                # Icon Composer .icon bundle + exports
  scripts/              # icon build pipeline
  docs/                 # landing page (tiagojct.eu/loomings)
  .github/workflows/    # release automation
```

## Stack

- **Tauri v2** — Rust shell + system WKWebView (no Chromium)
- **Vite 5** — frontend bundler
- **CodeMirror 6** — editor with lezer markdown grammar
- **markdown-it** — preview renderer
- **notify** (Rust) — external file watcher

## License

MIT — see [LICENSE](LICENSE).
