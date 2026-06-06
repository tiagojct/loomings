# LinkedIn launch post — Loomings v1.0.0

**Format:** single image (the OG card at docs/assets/og.png works well as preview).
**Best posted:** Tuesday or Wednesday morning, 09:00–11:00 your timezone.
**Length:** ~1,300 chars (LinkedIn cuts off at ~210 chars without "see more" but rewards medium-long posts).
**Engagement prompt:** the closing question.

---

## Post body

Today I released Loomings v1.0.0 — a markdown writing app for macOS, Windows, and Linux.

It is what I wanted from a writing app and could not quite find. A blank page that loads instantly. Real markdown in the editor: bold reads bold, headings read heading, code reads code. A focus mode that dims everything outside the current sentence. An outline you can jump to with ⌘P. Word counts and a word goal if you want one. No cloud sync, no account, no AI assistant pestering the margin.

The name comes from the first chapter of Moby-Dick. "Call me Ishmael" is in that chapter. The app opens with that paragraph as the bundled example.

Under the hood: Tauri 2 (Rust shell, system WebView, no bundled Chromium), CodeMirror 6 (lezer markdown grammar, native undo, IME-safe), markdown-it for the preview. The macOS build is about twelve megabytes and idles at thirty of RAM. The previous Electron prototype was 180 MB. Six platform installers (.dmg / .msi / .exe / .deb / .AppImage / .rpm) ship from a single tag push.

MIT licensed. Built solo in spare evenings. The whole thing is on GitHub.

Install on macOS with Homebrew:

  brew install --cask --no-quarantine tiagojct/loomings/loomings

Other platforms and source: tiagojct.eu/loomings

If you write — research notes, essays, books, journal — what is the smallest set of features your editor must have?

#markdown #writingapps #indiedev #opensource #tauri #rust #macos #windows #linux #productivity

---

## Notes

- Keep the URL on its own line; LinkedIn renders link cards better when the URL is isolated.
- The OG card (`docs/assets/og.png`) should attach automatically when LinkedIn fetches the page.
- If the card does not render, paste `https://tiagojct.eu/loomings` first, wait for the preview to load, then write the body and remove the bare URL.
- After publishing, comment from your personal account with a screenshot of the app — LinkedIn promotes posts whose author comments first.
