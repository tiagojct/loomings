# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Loomings is a minimalist Markdown desktop writing app (macOS/Windows/Linux). Tauri 2 shell (Rust backend, system WebView) + a plain-JS/Vite/CodeMirror 6 frontend. No framework, no bundled Chromium. The entire app is two source files:

- `src/editor.js` (~1200 lines) — the whole frontend: CodeMirror setup, themes, plugins, IPC wrappers, event listeners, UI (palette/about/preview/statusbar), boot sequence.
- `src-tauri/src/lib.rs` (~800 lines) — the whole backend: IPC commands, native menu, file watcher, update check, launch-file plumbing.

Everything else (`src/index.html`, `src/style.css`, config, icons, docs) is supporting.

## Commands

```sh
npm install
npm run dev        # tauri dev — Vite on 127.0.0.1:1420 + Rust hot reload
npm run build      # tauri build — installers land in src-tauri/target/release/bundle/
npm run vite:dev   # frontend only, no Rust shell (rarely useful — no IPC)
```

Rust tests (there are no JS tests):

```sh
cargo test --manifest-path src-tauri/Cargo.toml
cargo test --manifest-path src-tauri/Cargo.toml parse_semver_ordering   # single test
```

First Rust compile is 3-5 min; incremental builds are seconds. Linux build deps are listed in README.md.

## Architecture: the frontend/backend contract

The two files talk over two Tauri channels. Understand this before adding any feature.

- **JS → Rust: `invoke(command, args)`.** Every `#[tauri::command]` in `lib.rs` is registered in the `generate_handler![...]` list inside `run()`. In `editor.js` these are wrapped one-to-one by `ipc*` helper functions (`ipcSaveFile`, `ipcWatchFile`, etc.) near the top — call those, not raw `invoke`, so error handling stays consistent.
- **Rust → JS: `app.emit(event, payload)` / `listen(event, cb)`.** The native menu lives entirely in Rust (`build_menu`). It carries no logic: each menu click in `on_menu_event` just `emit`s a string event, which a `listen(...)` in `registerListeners()` maps to a JS handler. Window close and macOS file-open also emit events this way.

**To add a menu-driven feature you touch four places:** (1) a `MenuItemBuilder` + `.item()` in `build_menu`, (2) a match arm in `on_menu_event` that `emit`s an event, (3) a `listen(...)` line in `registerListeners()`, (4) the JS handler function. Keyboard-only features (no menu) skip 1-2 and bind in the `keydown` handler in `editor.js` instead.

## Two flows that are easy to break

**Launch-with-file (open a `.md` from Finder/Explorer).** Handled by `AppState.pending_launch_file` + `frontend_ready` in `lib.rs`. On non-macOS the setup hook reads argv; on macOS it comes through `RunEvent::Opened` (Apple Events, macOS-only — gate any code there with `#[cfg(target_os = "macos")]`). Cold launch stashes the path into the slot; JS boot drains it via `ipcTakeLaunchFile()` *before* offering scratch recovery (an explicitly-opened file wins over "recover yesterday's draft"). Once JS calls `ipcFrontendReady()`, a warm "Open With" emits `file-opened` directly. Don't reorder the boot IIFE at the bottom of `editor.js`.

**Close / quit.** `on_window_event` always calls `api.prevent_close()` and emits `request-close`; JS shows the unsaved-changes prompt and either calls `ipcConfirmQuit()` (which exits the process) or does nothing (window stays open). There is deliberately **no** timing/state-machine shortcut — the old "double-tap within 2s bypasses the prompt" pattern was the v1.0.0 data-loss bug. Keep it stateless.

**Scratch buffer (crash recovery).** JS autosaves the buffer to a scratch file every ~2s (`ipcSaveScratch`). It is deleted on clean exit (`RunEvent::ExitRequested`/`Exit` in `lib.rs`), so a surviving scratch file on next launch means a crash → offer recovery.

## Editor internals (editor.js)

- Markdown renders *in place* — bold looks bold, headings are sized — via a highlight style and theme built from a palette (`makeHighlight`, `makeTheme`) rather than a preview pane. Preview (⌘⇧P) is a separate `markdown-it` render.
- Custom CodeMirror extensions: `frontmatterPlugin` (dims YAML frontmatter), `sentenceFocusPlugin` (focus mode), `smartTypographyHandler` (an `inputHandler` converting quotes/`--`/`...`). Font size and theme are swapped live through `Compartment`s.
- Themes: two palettes (Pequod navy dark / parchment light) plus system-follow; applied via a `data-theme` attribute and a `matchMedia` listener.
- Preview sanitizes URLs by overriding markdown-it's `link_open` and `image` renderer rules — preserve that when touching preview.

## Gotchas

- **Version lives in three files** and must stay in sync: `package.json`, `src-tauri/tauri.conf.json`, `src-tauri/Cargo.toml`. The update check compares the running version against the latest GitHub release.
- **CSP is strict** (`tauri.conf.json` → `app.security.csp`). Any new outbound host must be added to `connect-src` (currently only `api.github.com`, for the update check via the `ureq` client). New capabilities/permissions go in `src-tauri/capabilities/default.json`.
- **File associations** (`.md/.markdown/.qmd/.rmd/.txt`) are declared in `tauri.conf.json` → `bundle.fileAssociations`; the actual open is driven by the launch-with-file flow above.
- Builds are **unsigned** (no Apple Developer ID). Update check never auto-installs — macOS quarantine would break it. Don't add auto-update.
- Release automation is a single GitHub Actions workflow, `.github/workflows/release.yml` (4 platforms).
