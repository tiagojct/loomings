# Loomings — Launch Readiness Audit

v0.2.3 → v1.0.0 · 2026-06-06

## Summary

Loomings is a polished, focused Markdown editor. ~2,180 lines of code (JS + Rust + CSS), ~12 MB macOS binary, 4-platform CI. The app is stable and feature-complete, with a distinctive design language. This document catalogues what is ready, what needs attention before a v1.0.0 public launch, and what should be deferred to post-launch.

---

## What is excellent

### Design system — the Pequod theme

Two complete, pixel-consistent themes sharing the Pequod palette. Dark mode ("below deck"): `#061826` → `#0E2D44` → `#02101B` with amber accents (`#BD8C68`). Light mode ("parchment"): `#F1E7D2` → `#F8F0DD` with deeper amber (`#8B6348`). The palette is applied consistently across every surface:

- CodeMirror editor themes (two complete `EditorView.theme` configurations)
- Syntax highlighting (`HighlightStyle` with `@lezer/highlight` tags mapped to Pequod colors)
- CSS custom properties (`:root`, `[data-theme="dark"]`, `[data-theme="light"]`)
- Preview rendering (headings, code blocks, blockquotes, links — all Pequod-mapped)
- Modal surfaces: about dialog, outline palette, update banner
- Statusbar, titlebar, and chrome

Theme transitions are smooth (`transition: background 0.25s ease`) and the system-follow mode listens to `prefers-color-scheme: dark` change events. Every color token is deliberate — no hardcoded hex values outside the palette definitions.

### Code quality

**Rust (`src-tauri/src/lib.rs`, 692 lines).** Clean, idiomatic Tauri v2 code. Highlights:

- `AppState` with `Mutex<Option<FileWatcher>>` for safe concurrent access to the debounced file watcher
- `tokio::sync::oneshot` channels for async dialog callbacks (open/save-as)
- `parse_semver` for update checking with GitHub Releases API
- Proper menu construction with platform-aware behavior (`#[cfg(target_os = "macos")]`)
- Double-tap-close guard: requires two close attempts within 2 seconds, preventing accidental data loss
- Scratch buffer persistence for crash recovery (`scratch.json` in app data dir)
- External file watcher with `notify-debouncer-mini` (400ms debounce, canonical path matching)

**JavaScript (`src/editor.js`, 1,061 lines).** Single-file architecture, well-sectioned with comment dividers. Highlights:

- CodeMirror 6 setup with `Compartment` for dynamic reconfiguration (font size, theme, highlight style)
- `ViewPlugin` implementations for frontmatter dimming and sentence-level focus mode
- Sentence-level focus dimming: regex-based sentence boundary detection within the current paragraph, not just paragraph-level — a craft detail
- Smart typography handler: `"` → `"`/`"`, `'` → `'`/`'`, `--` → `—`, `...` → `…` — all via `EditorView.inputHandler`
- Outline palette: `syntaxTree` traversal for ATX and Setext headings, fuzzy filtering, keyboard navigation (↑↓EnterEsc)
- Word goal system: 7 presets (0/250/500/750/1000/2000/5000), progress percentage in statusbar

**CSS (`src/style.css`, 423 lines).** All custom properties, no framework. Clean component separation:

- Titlebar (drag region for Tauri overlay)
- Editor container with centered column width cycling (wide/normal/narrow)
- Full-featured preview stylesheet (headings, code, blockquotes, lists, horizontal rules)
- Palette overlay with backdrop blur and item indentation by heading level
- About modal with centered layout, serif name, monospace version
- Update banner as a fixed bottom toast
- Focus mode: titlebar/statusbar fade to `opacity: 0` with hover reveal

### Feature completeness

| Feature | Implementation |
|---------|---------------|
| Real-time markdown syntax in editor | CodeMirror 6 with `@codemirror/lang-markdown` + lezer grammar |
| Markdown shortcuts | ⌘B/⌘I wrap, ⌘\` code, ⌘K link — all toggle-aware (unwrap if already wrapped) |
| Smart list auto-continue | `-`, `*`, `+`, `1.`, `>` extend on Enter; double-Enter exits |
| Smart typography | Curly quotes, em-dash, ellipsis — toggleable via View menu |
| YAML frontmatter detection | Dimmed styling for `---`…`---` blocks at document start |
| Outline palette (⌘P) | Fuzzy-jump to any heading with keyboard navigation |
| Find/Replace (⌘F) | CodeMirror search panel with regex, case sensitivity, replace |
| Focus mode (⌘⇧D) | Dims everything outside the current sentence — not just paragraph |
| Preview (⌘⇧P) | Full markdown-it rendering with URL sanitization |
| Stats panel (⌘⇧L) | Word count, character count, line count — with word goal progress |
| Word goal (⌘⇧G) | 7 presets cycling: off → 250 → 500 → 750 → 1000 → 2000 → 5000 |
| Column width (⌘⇧W) | Cycles wide (900px) → normal (660px) → narrow (500px) |
| Theme cycle (⌘⇧T) | Cycles system → light → dark |
| Font size (⌘=/⌘-) | 11px–24px range, persisted |
| Auto-save | 2-second debounce after last edit, for named files only |
| Crash recovery | Scratch buffer saved on every keystroke, restored on next launch |
| External file watcher | Prompts reload if file changes on disk (notify debouncer, 400ms) |
| Recent files | File menu submenu, last 10, persisted to `recent.json` |
| Update check | Banner toast if newer GitHub release exists; manual check in Help menu |
| About modal | Custom HTML modal + populated macOS About panel (Help menu) |
| Open example | Bundled Moby-Dick chapter 1 as Tauri resource |
| Fullscreen | F11 toggle |
| DevTools | ⌘⌥I (debug builds only via `#[cfg(debug_assertions)]`) |
| Window title | `Loomings — filename.md` for named files, `Loomings` for scratch |
| Close guard | Double-tap ⌘W/⌘Q to confirm (state-guarded, 2s window) |
| Dirty indicator | Amber dot (`•`) in statusbar when buffer has unsaved changes |

### CI/CD

**Platform matrix:** macOS ARM (macos-14), macOS x64 (macos-13), Linux x64 (ubuntu-22.04), Windows x64 (windows-latest).

**Workflow (`release.yml`):**
- Triggers on tag push (`v*`) and manual `workflow_dispatch`
- Rust caching via `swatinem/rust-cache@v2`
- Linux system dependencies installed conditionally
- Release artifacts uploaded via `softprops/action-gh-release@v2` as draft
- Workflow dispatch uploads as build artifacts (not releases)
- Unsigned — documented with clear Gatekeeper workaround

### Landing page

`docs/index.html` — served at `tiagojct.eu/loomings`. Editorial tone, Pequod-themed, opens with "Call me Ishmael." Clear sections: what it is, what it is not, built with, Gatekeeper fix. Single HTML file with inline CSS. Screenshot included.

### Documentation

`README.md` is comprehensive: install table per platform, feature list with keyboard shortcuts, build-from-source instructions, project layout diagram, stack description, license. A model of what a README should be.

---

## Pre-launch blockers

These should be addressed before tagging v1.0.0.

### 1. Unsigned macOS builds — friction point

**Severity:** high · **Effort:** documentation only (unless purchasing Apple Developer ID)

macOS Sequoia (15.x) and Tahoe (26.x) block unsigned apps even with right-click → Open. The documented workaround (`xattr -dr com.apple.quarantine /Applications/Loomings.app`) works but requires Terminal. Non-technical users will hit a wall.

**Options:**
- Keep current approach, emphasize the workaround prominently on landing page and README
- Purchase Apple Developer ID ($99/year) for notarization — eliminates the friction entirely
- Distribute via Homebrew cask, which handles quarantine automatically

**Recommendation:** Ship unsigned for v1.0.0. Add Homebrew cask as a post-launch quick win. Consider Developer ID for v1.1.0 if adoption justifies it.

### 2. GitHub releases are draft-only

**Severity:** high · **Effort:** 5 minutes per release

The CI workflow creates releases as `draft: true`. The 4 existing releases (v0.2.0–v0.2.3) are all drafts with no release notes. The update checker hits `/releases/latest` which returns the most recent *published* release — not draft. If no release is published, the update checker returns nothing.

**Action:**
1. Write release notes for v1.0.0
2. Tag and push `v1.0.0` to trigger CI
3. After CI completes, review the draft release, add notes, click "Publish"

### 3. No release notes exist

**Severity:** medium · **Effort:** 30 minutes

Users downloading from the releases page see empty release bodies. For v1.0.0, a proper changelog communicates maturity.

**Template:**
```
## What's new in v1.0.0

### Editor
- ...

### Themes
- ...

### Files
- ...

### App
- ...

### Fixes
- ...
```

---

## Pre-launch improvements

These are not blockers but would improve the v1.0.0 experience.

### 4. Version bump: 0.2.3 → 1.0.0

**Effort:** 5 minutes

Files to update:
- `package.json` → `"version": "1.0.0"`
- `src-tauri/Cargo.toml` → `version = "1.0.0"`
- `src-tauri/tauri.conf.json` → `"version": "1.0.0"`

The app has been stable through 4 releases. Feature set is complete for a writing-focused editor. v1.0.0 signals this.

### 5. Add `.qmd` and `.rmd` to file filters

**Effort:** 2 minutes

The file open/save dialogs filter for `.md`, `.markdown`, `.txt`. The target audience (academics, researchers) uses Quarto (`.qmd`) and R Markdown (`.rmd`). Both are plain-text Markdown dialects.

**Files to change:**
- `src-tauri/src/lib.rs`: `open_file_dialog` and `save_file_as` — add `"qmd"` and `"rmd"` to filter arrays

### 6. Publish the landing page

**Effort:** 5 minutes

`docs/index.html` and `docs/style.css` exist but need to be deployed to `tiagojct.eu/loomings/`. The repo is already configured with GitHub Pages (the `docs/` folder). Verify the Pages settings are enabled and pointing to `/docs`.

### 7. macOS About panel — icon path

**Effort:** check only

The macOS About panel (populated via `AboutMetadataBuilder`) references the app icon. Verify the icon displays correctly in the native About dialog on macOS. The `set_icon` for the app bundle needs to be set; Tauri v2 handles this via `bundle.icon` in `tauri.conf.json` — already configured.

---

## Post-launch (v1.1.0+)

### Spellcheck integration

**Priority:** medium · **Effort:** 1–2 hours

No spellcheck is the most noticeable feature gap for a writing app. Options:
- **Browser-native spellcheck:** Enable `spellcheck` attribute on the CodeMirror contenteditable. Simplest, but limited styling and language support.
- **`@codemirror/spellcheck` extension:** Wraps the browser's spellcheck API with CodeMirror decorations. Better integration.
- **Third-party (cspell, typo.js):** More control, heavier dependency.

Recommend starting with `@codemirror/spellcheck` — it respects the browser's dictionary and adds red squiggly underlines.

### Typewriter scrolling

**Priority:** medium · **Effort:** 2–3 hours

Writing-focused editors (iA Writer, Ulysses, Byword) keep the active line centered vertically. CodeMirror supports this via `EditorView.scrollIntoView` with `y: "center"`. A `ViewPlugin` that calls this on cursor movement would implement it.

### Preferences window

**Priority:** low · **Effort:** 4–6 hours

All settings are keyboard-shortcut-driven with no discoverable UI. A Preferences window (⌘,) would expose:
- Theme selection (system/light/dark)
- Font size slider
- Smart typography toggle
- Default column width
- Word goal

This is a significant UX improvement for non-power-users.

### Homebrew cask

**Priority:** medium · **Effort:** 1–2 hours (first time), 5 minutes per update

A Homebrew cask formula (`loomings.rb`) in `homebrew-cask` would let macOS users install with:
```sh
brew install --cask loomings
```

Homebrew handles quarantine automatically. The formula is a Ruby file pointing at the latest GitHub release `.dmg`.

### Syntax highlighting in preview

**Priority:** low · **Effort:** 1–2 hours

Code blocks in the preview render as plain monospace text. Adding `highlight.js` or `prism.js` to `markdown-it` via `markdown-it-highlightjs` would colorize code blocks. Impact is moderate — the primary use case is prose writing, not code display.

### Auto-save for untitled (scratch) buffers

**Priority:** low · **Effort:** 1 hour

Auto-save currently only triggers for named files. Untitled scratch buffers are recovered on crash via `scratch.json` but are not periodically saved to a temp location. This is fine for crash recovery but means Force Quit loses work. A temp-file auto-save for unnamed buffers would close this gap.

### `.editorconfig` or project settings

**Priority:** low · **Effort:** 3–4 hours

No way to persist editor settings per-project or per-directory (e.g., different font sizes for different writing projects). An `.editorconfig`-style file or a `.loomings.json` in the working directory would enable this.

### Line numbers toggle

**Priority:** low · **Effort:** 30 minutes

CodeMirror supports line numbers natively via `lineNumbers()` extension. Some users expect a toggle. Currently no line numbers — a deliberate design choice for minimalism, but worth offering as an option.

### Word count for selection

**Priority:** low · **Effort:** 30 minutes

The stats panel shows total document word count. Showing word count for the current selection would be useful for writers tracking paragraph or section length.

---

## What to NOT add

Loomings derives its identity from what it omits. The landing page already states this: "No cloud sync. No account. No tracking. No newsletter. No themes marketplace. No AI assistant pestering the margin. No mobile companion."

Resist the temptation to add:
- Real-time collaboration or sync (use filesystem + git)
- Built-in file browser / project drawer (use Finder/Explorer)
- WYSIWYG mode (the split editor/preview already serves this)
- PDF export (use Pandoc externally)
- Plugin system (complexity cost exceeds benefit for this scope)
- AI features (explicitly anti-hype positioning is a strength)

---

## Launch checklist

- [ ] Bump version to 1.0.0 in package.json, Cargo.toml, tauri.conf.json
- [ ] Write v1.0.0 release notes
- [ ] Add `.qmd` and `.rmd` to file filters in lib.rs
- [ ] Verify landing page works at tiagojct.eu/loomings
- [ ] Verify macOS About panel shows correct icon
- [ ] Tag `v1.0.0` and push
- [ ] Wait for CI to complete (4 platforms, ~15 minutes)
- [ ] Review draft release, paste release notes, click "Publish"
- [ ] Announce (blog post, Mastodon, LinkedIn, Hacker News?)

---

## Landing page audit

`docs/index.html` + `docs/style.css` — served at `tiagojct.eu/loomings`

The landing page is already strong: editorial tone, Pequod palette, dark mode support, Source Serif 4 typography, drop cap, no marketing fluff. The "What is not" section is a manifesto — rare and valuable. However, for a v1.0.0 launch, several improvements would reduce friction and communicate the product more effectively.

### 1. Single screenshot, zero feature visuals

**Current:** One screenshot showing the editor with Moby-Dick chapter 1. This sells the tone but not the features. A first-time visitor cannot see focus mode, the outline palette, the preview, or the word goal — these are invisible until the app is installed.

**Recommendation:** Add two additional screenshots, small and inline with the relevant sections:
- One showing focus mode (dimmed text with active sentence highlighted), placed near the focus mode mention in "What is there"
- One showing the preview pane, placed near the preview mention

Format: PNG, ~800px wide, same border/shadow treatment as the existing `.shot` figure. No carousel — static, editorial placement within the text flow.

### 2. Generic "Download" button

**Current:** A single "Download" button linking to `github.com/tiagojct/loomings/releases/latest`. Non-technical users land on a page of technical filenames (`aarch64.dmg`, `amd64.deb`, `x64-setup.exe`) with no guidance. Drop-off at this step is likely high.

**Recommendation:** Replace with platform-specific buttons or a segmented control:

```
[macOS Apple Silicon]  [macOS Intel]  [Windows]  [Linux .deb]  [Other Linux]
```

Each button links directly to the asset URL on the latest GitHub release. The URLs can be hardcoded per release or generated via a small build script that fetches `/releases/latest` and extracts asset download URLs. For v1.0.0, hardcoding is acceptable — update with each release.

Style: keep the ink-on-parchment aesthetic. No OS logos. Platform names in Source Serif, monospace file extensions in JetBrains Mono.

### 3. Dark mode support is incomplete

**Current:** The CSS has `@media (prefers-color-scheme: dark)` with correct palette values. But:
- The `<meta name="theme-color">` tag only specifies the light value (`#F1E7D2`). In dark-mode browsers, the address bar stays parchment-colored against a dark page — visually broken.
- There is no manual theme toggle. For a product page, a sun/moon toggle is expected, though system-respecting is acceptable for a static page.

**Recommendation:**
- Add: `<meta name="theme-color" media="(prefers-color-scheme: dark)" content="#0B1F2D">`
- Optional: a small theme toggle in the header using a CSS-class-based override + `localStorage`

### 4. No keyboard shortcuts reference

**Current:** The README has a full shortcuts table. The landing page has none. Someone who reads the feature descriptions ("focus mode that dims everything…") has to go to GitHub to learn how to activate it.

**Recommendation:** Add a compact "How it works" section with 5–6 key shortcuts in visual pills:

```html
<div class="shortcuts">
  <span class="key"><kbd>⌘P</kbd> Outline</span>
  <span class="key"><kbd>⌘⇧D</kbd> Focus</span>
  <span class="key"><kbd>⌘⇧P</kbd> Preview</span>
  <span class="key"><kbd>⌘⇧W</kbd> Width</span>
  <span class="key"><kbd>⌘⇧T</kbd> Theme</span>
  <span class="key"><kbd>⌘⇧G</kbd> Goal</span>
</div>
```

Style each pill as an inline-flex container: JetBrains Mono for the keys, Source Serif for the labels, subtle border, matching the ink-on-parchment aesthetic. No background fill — ghost buttons in the same style as the rest of the page.

### 5. Redundant @font-face declaration

**Current:** `style.css` has both a manual `@font-face` block for Source Serif 4 (lines 30–37) and a `@import` from Google Fonts (line 39). The `@font-face` `src: url(...)` points to a Google Fonts CSS URL, not a font file. This does not work — the browser ignores it because the URL returns CSS, not a font binary. The `@import` on line 39 loads the font correctly, making the `@font-face` block dead code.

**Recommendation:** Remove the manual `@font-face` block (lines 30–37). The `@import` alone is sufficient. If `local()` prioritization is desired, use a proper `@font-face` with `local()` in `src:` and a font file URL or `url()` pointing to the Google Fonts CSS — but this is unnecessary complexity for a single-page static site.

### 6. "What is not" section deserves visual weight

**Current:** A single paragraph listing anti-features. This is the strongest piece of positioning on the page — it defines what Loomings refuses to be. It should not look like body text.

**Recommendation:** Render as a styled list with em-dash or multiplication-sign bullets:

```html
<ul class="not-list">
  <li>No cloud sync</li>
  <li>No account</li>
  <li>No tracking</li>
  <li>No newsletter</li>
  <li>No themes marketplace</li>
  <li>No AI assistant pestering the margin</li>
  <li>No mobile companion</li>
</ul>
```

Style: no standard bullets. Use `::before { content: "—"; }` with the accent color. Slightly larger font size than body text (20px). Each item on its own line with comfortable spacing. The list should feel deliberate — each line is a commitment.

### 7. Footer is too minimal

**Current:** Only name, tagline, and a short horizontal rule. No link to GitHub, releases, or the main site. For a product page, the footer should provide the user's next action.

**Recommendation:**

```
Loomings · v1.0.0 · by Tiago Jacinto · GitHub · tiagojct.eu
```

App name links to the top of the page. Version links to the GitHub releases page. Author name links to tiagojct.eu. GitHub links to the repo. Keep the horizontal rule. Keep the italic style. Add version number for transparency.

### 8. Open Graph image is the app icon (84×84)

**Current:** `og:image` points to `assets/icon.png` — an 84×84 app icon. When shared on Twitter, Mastodon, LinkedIn, or iMessage, the preview card shows a tiny square icon with no text. This is a missed opportunity for every social share.

**Recommendation:** Create a dedicated social share image: 1200×630px, dark parchment background (`#0B1F2D` or `#F1E7D2`), with the app name ("Loomings") in italic Source Serif Display, the tagline below in regular weight, and the app icon small in a corner. The image communicates the product identity at a glance. Tools: any image editor, or generate via HTML→screenshot automation.

### 9. No version number visible

**Current:** The page mentions "v0.2.3" nowhere. For a launched product, showing the current version builds trust (this is maintained, not abandonware) and helps users identify whether they have the latest.

**Recommendation:** Add the version number to the header (below the subtitle: "v1.0.0") or the footer. Subtle, muted color, monospace font. Updates with each release tag.

### Landing page improvement plan (ordered by impact)

| # | Change | Effort | Impact |
|---|--------|--------|--------|
| 1 | Platform-specific download buttons | 30 min | High — reduces install friction |
| 2 | +2 screenshots (focus mode, preview) | 20 min | High — shows the product |
| 3 | Keyboard shortcuts section | 15 min | Medium — communicates usability |
| 4 | Style "What is not" as a list | 10 min | Medium — reinforces positioning |
| 5 | Fix redundant @font-face | 5 min | Low — cleanup |
| 6 | Meta theme-color for dark mode | 2 min | Low — polish |
| 7 | Footer with links and version | 10 min | Low — navigation and trust |
| 8 | Social share image (1200×630) | 30 min | Medium — social reach |
| 9 | Version number in header | 2 min | Low — trust signal |
| **Total** | | **~2 hours** | |

---

## Updated launch checklist

- [ ] Bump version to 1.0.0 in package.json, Cargo.toml, tauri.conf.json
- [ ] Write v1.0.0 release notes
- [ ] Add `.qmd` and `.rmd` to file filters in lib.rs
- [ ] Landing page: platform-specific download buttons (item 1)
- [ ] Landing page: feature screenshots (item 2)
- [ ] Landing page: keyboard shortcuts section (item 3)
- [ ] Landing page: style "What is not" list (item 4)
- [ ] Landing page: fix @font-face + theme-color (items 5, 6)
- [ ] Landing page: footer + version number (items 7, 9)
- [ ] Landing page: social share image (item 8)
- [ ] Verify landing page works at tiagojct.eu/loomings
- [ ] Verify macOS About panel shows correct icon
- [ ] Tag `v1.0.0` and push
- [ ] Wait for CI to complete (4 platforms, ~15 minutes)
- [ ] Review draft release, paste release notes, click "Publish"
- [ ] Announce (blog post, Mastodon, LinkedIn, Hacker News?)

---

## File inventory

```
loomings/
  src/
    editor.js           # 1,061 lines — all frontend logic
    index.html          # 66 lines — DOM structure
    style.css           # 423 lines — Pequod theme, all components
    icon.png            # App icon (Vite-served, shown in About modal)
  src-tauri/
    src/lib.rs          # 692 lines — IPC commands, menu, watcher, update check
    src/main.rs         # 5 lines — entry point
    tauri.conf.json     # Window config, bundle, icons, macOS overlay
    Cargo.toml          # Dependencies, release profile (optimized)
    capabilities/       # Tauri permission allowlist
    icons/              # ICNS, ICO, sized PNGs
  docs/
    index.html          # Landing page (tiagojct.eu/loomings)
    style.css           # Landing page styles
    assets/             # Screenshot, icon
  examples/
    loomings.md         # Moby-Dick chapter 1 (bundled resource)
  scripts/
    build-icon.sh       # macOS icon generation pipeline
  .github/workflows/
    release.yml         # 4-platform CI, draft releases on tag push
```

---

*Audit by Basílio (Hermes Agent), 2026-06-06*
