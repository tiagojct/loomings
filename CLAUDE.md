# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Loomings is a minimalist Markdown writing app that ships two ways from one
frontend: a Tauri 2 desktop app (macOS/Windows/Linux) and a static web build
(`docs/` landing page + the editor at `/app`, deployed via Docker/nginx).
Plain-JS/Vite/CodeMirror 6 frontend, no framework, no bundled Chromium.

- `src/editor.js` (~1600 lines) — the whole editor: CodeMirror setup,
  themes, plugins, event listeners, UI (palette/about/preview/statusbar/
  web toolbar), boot sequence. Platform-agnostic — never imports
  `@tauri-apps/*` or browser-only APIs directly.
- `src/platform.js` — picks `platform-tauri.js` or `platform-web.js` at
  runtime via `'__TAURI_INTERNALS__' in window`, re-exported as `isTauri`
  plus a fixed set of named functions both adapters implement.
- `src/platform-tauri.js` — desktop file I/O/menu/window, thin wrappers
  around `invoke()`/Tauri plugins.
- `src/platform-web.js` — browser file I/O via the File System Access API
  (Chromium; `<input type=file>`/download fallback elsewhere) and
  IndexedDB for scratch/recents.
- `src-tauri/src/lib.rs` (~950 lines) — the whole desktop backend: IPC
  commands, native menu, file watcher, update check, launch-file plumbing.
  Not part of the web build at all.

Everything else (`src/index.html`, `src/style.css`, config, icons, docs,
`Dockerfile`/`nginx.conf`/`docker-compose.yml`) is supporting.

## Commands

```sh
npm install
npm run dev        # tauri dev — Vite on 127.0.0.1:1420 + Rust hot reload
npm run build      # tauri build — installers land in src-tauri/target/release/bundle/
npm run vite:dev   # frontend only, desktop-shaped (no Rust shell) — platform-web.js loads
npm run vite:build -- --base /app/   # web build, matches the Docker /app mount
```

Rust tests (there are no JS tests):

```sh
cargo test --manifest-path src-tauri/Cargo.toml
cargo test --manifest-path src-tauri/Cargo.toml parse_semver_ordering   # single test
```

First Rust compile is 3-5 min; incremental builds are seconds. Linux build deps are listed in README.md.

## Architecture: the platform seam

`editor.js` never touches Tauri or browser file/window APIs directly — it
calls a fixed set of `ipc*`/`init*` functions imported from `platform.js`
(e.g. `ipcSaveFile`, `ipcWatchFile`, `initDragDrop`), which re-exports
whichever of `platform-tauri.js` / `platform-web.js` matches the runtime.
**Adding or changing one of these functions means updating both adapters**
(or adding a no-op stub in the one that doesn't support it) — `platform.js`
just destructures both into the same names, so a missing export is
`undefined` at the call site, not a build error.

On desktop, the two Tauri channels `platform-tauri.js` wraps:

- **JS → Rust: `invoke(command, args)`.** Every `#[tauri::command]` in `lib.rs` is registered in the `generate_handler![...]` list inside `run()`.
- **Rust → JS: `app.emit(event, payload)` / `listen(event, cb)`.** The native menu lives entirely in Rust (`build_menu`). It carries no logic: each menu click in `on_menu_event` just `emit`s a string event, which a `listen(...)` in `registerListeners()` (in `editor.js`, unchanged between platforms) maps to a JS handler. Window close and macOS file-open also emit events this way. On web, `listen()` is a no-op subscribe — nothing emits these events there; the web toolbar calls the same handler functions directly instead.

**To add a menu-driven feature (desktop) you touch four places:** (1) a `MenuItemBuilder` + `.item()` in `build_menu`, (2) a match arm in `on_menu_event` that `emit`s an event, (3) a `listen(...)` line in `registerListeners()`, (4) the JS handler function. Keyboard-only features (no menu) skip 1-2 and bind in the `keydown` handler in `editor.js` instead — those work on both platforms for free. If the feature needs a web-only affordance (no native menu there), add a button to the toolbar in `index.html`/`style.css` (`#web-toolbar`, shown via `body:not(.tauri)`) wired directly to the handler function.

## Two flows that are easy to break

**Launch-with-file (open a `.md` from Finder/Explorer).** Handled by `AppState.pending_launch_file` + `frontend_ready` in `lib.rs`. On non-macOS the setup hook reads argv; on macOS it comes through `RunEvent::Opened` (Apple Events, macOS-only — gate any code there with `#[cfg(target_os = "macos")]`). Cold launch stashes the path into the slot; JS boot drains it via `ipcTakeLaunchFile()` *before* offering scratch recovery (an explicitly-opened file wins over "recover yesterday's draft"). Once JS calls `ipcFrontendReady()`, a warm "Open With" emits `file-opened` directly. Don't reorder the boot IIFE at the bottom of `editor.js`.

**Close / quit.** `on_window_event` always calls `api.prevent_close()` and emits `request-close`; JS shows the unsaved-changes prompt and either calls `ipcConfirmQuit()` (which exits the process) or does nothing (window stays open). There is deliberately **no** timing/state-machine shortcut — the old "double-tap within 2s bypasses the prompt" pattern was the v1.0.0 data-loss bug. Keep it stateless.

**Scratch buffer (crash recovery).** JS autosaves the buffer to a scratch file every ~2s (`ipcSaveScratch`). It is deleted on clean exit (`RunEvent::ExitRequested`/`Exit` in `lib.rs`), so a surviving scratch file on next launch means a crash → offer recovery.

## Editor internals (editor.js)

- Markdown renders *in place* — bold looks bold, headings are sized — via a highlight style and theme built from a palette (`makeHighlight`, `makeTheme`) rather than a preview pane. Preview (⌘⇧P) is a separate `markdown-it` render.
- Custom CodeMirror extensions: `frontmatterPlugin` (dims YAML frontmatter), `sentenceFocusPlugin` (focus mode), `smartTypographyHandler` (an `inputHandler` converting quotes/`--`/`...`). Font size and theme are swapped live through `Compartment`s.
- Themes: three families (Pequod, Glauca, Try-Works — `PALETTES` in `editor.js`), each dark/light, plus system-follow; applied via `data-theme`/`data-palette` attributes and a `matchMedia` listener. Family picker is a native menu on desktop, the toolbar's Theme button (cycles) on web.
- Preview sanitizes URLs by overriding markdown-it's `link_open` and `image` renderer rules — preserve that when touching preview.

## Gotchas

- **Version lives in three files** and must stay in sync: `package.json`, `src-tauri/tauri.conf.json`, `src-tauri/Cargo.toml`. The update check compares the running version against the latest GitHub release.
- **CSP is strict** (`tauri.conf.json` → `app.security.csp`). Any new outbound host must be added to `connect-src` (currently only `api.github.com`, for the update check via the `ureq` client). New capabilities/permissions go in `src-tauri/capabilities/default.json`.
- **File associations** (`.md/.markdown/.qmd/.rmd/.txt`) are declared in `tauri.conf.json` → `bundle.fileAssociations`; the actual open is driven by the launch-with-file flow above.
- Builds are **unsigned** (no Apple Developer ID). Update check never auto-installs — macOS quarantine would break it. Don't add auto-update. The update check is a no-op on web (`ipcCheckForUpdate` in `platform-web.js` always returns null — a hosted page is always latest on reload).
- Two release pipelines: `.github/workflows/release.yml` builds desktop installers (macOS arm64, Windows, Linux — Intel Mac dropped, its `macos-13` CI runner queue was unreliable) on version tags. `.github/workflows/docker-publish.yml` builds the web image and pushes to `ghcr.io/tiagojct/loomings` on pushes to main and version tags; `:latest` only moves on tags, so the VPS's watchtower (`docker-compose.yml`) only redeploys on releases.
- Web build's asset paths depend on `vite build --base /app/` matching `nginx.conf`'s `/app` mount — if either side's path changes, they must change together (see `Dockerfile`'s comment on the `--base` flag).
