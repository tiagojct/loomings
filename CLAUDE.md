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
- `src/browser.js` — everything that touches the browser: File System
  Access API with picker/download fallback, IndexedDB (scratch, recents,
  documents), `document.title`, `window.confirm`, launch queue, service
  worker registration.
- `src/palettes.js` — the four colour families. The only place a colour
  lives; `editor.js` writes them onto `<html>` as CSS variables and
  `style.css` reads those (it keeps only a Pequod pre-script fallback).
- `src/share.js` — document ⇄ URL fragment. Pure, tested.
- `src/lessons.js` — index of `lessons/NN-slug.md` via `import.meta.glob`.
- `src/sw-template.js` + the plugin in `vite.config.js` — the service worker,
  emitted as `sw.js` with the build's asset list.

## Commands

```sh
npm install
npm run dev        # Vite dev server, http://127.0.0.1:1420/app/ (no service worker in dev)
npm test           # Vitest (src/**/*.test.js): palettes, share, lessons
npm run build      # dist/ — app at /app/, sw.js, manifest, icons
npm run preview    # serves dist/ at http://127.0.0.1:4173/app/ (service worker active)
```

`.claude/launch.json` has `loomings-dev` and `loomings-preview` for the
browser pane.

## Conventions that matter

- **`base` is `/app/`** in `vite.config.js`, and must match `nginx.conf`'s
  `/app` mount, the manifest's `scope`/`start_url`, and the service
  worker's `BASE`. Change them together.
- **Colours only in `palettes.js`.** Add a family there (dark + light, the
  ten `PALETTE_KEYS`, optional ink roles `heading`/`emphasis`/`code`/
  `marker`) and to `FAMILY_ORDER`; the theme menu, CodeMirror themes,
  CSS variables and HTML export all follow. `npm test` enforces WCAG
  floors per mode.
- **The document's home is one of three:** a file handle (`currentFile`,
  handle kept in `browser.js`), a browser document (`currentDocId`,
  IndexedDB), or nothing (untitled). `doSave` dispatches on that;
  `handleSave` picks a home for untitled buffers (file picker where the
  File System Access API exists, otherwise the browser). `loadFile`
  resets both and calls `forgetFile()` for content with no file behind it.
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
- **CDN cache:** Cloudflare fronts the site and caches `.js`/`.css` for the
  year nginx advertises. Only content-hashed assets may be long-cached;
  `sw.js` is registered by a versioned URL and served `no-cache`. The VPS
  DNS token cannot purge the cache.
- **Version** lives in `package.json` only. The service worker's cache
  name and the About dialog read it from there.
- Lessons are plain Markdown without raw HTML (the preview has
  `html: false`); the lessons test enforces it.
