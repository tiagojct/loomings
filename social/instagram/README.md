# Instagram playbook — @loomings.app (or @loomings.md)

A field guide for an Instagram account dedicated to Loomings. Designed
to work with one weekly post and the occasional Story, not a daily
content-machine grind.

---

## Account setup

### Handle
First choice: `@loomings.app` (.app TLD signals software, reads cleanly).
Backup:     `@loomings.md` (insider Markdown-nerd wink).
Avoid:      `@loomingsapp` (no separator, harder to read).

### Display name
`Loomings`

### Bio (150 character limit)

```
A markdown writing app for macOS, Windows, Linux.
The shapes loom before they take form.
↓ tiagojct.eu/loomings
```

That's 117 chars. Three lines. Last line is the link tease.

### Link
`tiagojct.eu/loomings` (single URL — Linktree-style services add a hop and look generic).

### Profile photo
Use the app icon — 1024×1024 PNG from `src-tauri/icons/icon.png`. Instagram crops it into a circle, which suits the dark navy / amber L well.

### Story highlight covers
Five circles, all matching the Pequod palette (navy background, amber line icons):

| Title | Glyph |
|---|---|
| Features | wrench |
| Shortcuts | keyboard |
| Themes | sun/moon split |
| The Name | open book |
| Install | downward arrow |

The covers can be made by drawing simple white-on-navy SVG icons at 1080×1920, saving as Story images, then setting them as highlight covers.

---

## Voice

Same as the landing page and the LinkedIn post — editorial, restrained, never marketing-shouty. Lowercase first word in captions. No emoji unless functional (✦ for separators is fine, ✨ is not). Em-dashes welcome. Pull quotes from the chapter when relevant.

What to avoid:
- "Excited to announce…"
- "Game-changer", "10x", "AI-powered"
- Emoji walls
- Numbered lists in captions (Instagram strips line breaks unevenly)
- Calls to action with "Link in bio 👆"

What to lean into:
- Melville quotes
- Specific shortcuts (the visual ⌘ ⇧ ⌥ symbols pop on white text)
- The Pequod palette
- Behind-the-scenes design decisions
- Side-by-side comparisons (Electron 180 MB → Tauri 12 MB)

---

## Content pillars

Three streams, rotate roughly evenly:

### 1. The writing app
Features, shortcuts, screenshots in action. The product itself.
Examples: focus-mode demo reel, the outline palette in motion, theme switch.

### 2. The name
Moby-Dick context. Why "Loomings". Public-domain quote graphics. The chapter that opens with "Call me Ishmael" is the namesake.
Examples: pull quotes on parchment, the bundled example file, "chapter 1 in your editor" carousels.

### 3. The making of
The icon evolution. Choice of Tauri over Electron. Design decisions. The point at which you committed to 1.0.0.
Examples: icon sketches → final, stack diagram, the build pipeline.

---

## Cadence

- **Launch week:** posts 01–04, two per day (morning + evening).
- **Week 2:** 3 posts (Mon, Wed, Fri).
- **Weeks 3–8:** 1 post per week + 2 Stories per week (Stories are casual — work-in-progress, palette tweaks, screenshots of writers using it).
- **After week 8:** drop to 1 post / fortnight. Stories whenever.

Time slot: posting times that consistently work for productivity / dev content are **Tuesday and Thursday 09:00–11:00 your timezone** (a research-aligned audience checks Instagram with morning coffee).

---

## Hashtag set

Two stacks. Pick 10–15 per post, mixing both.

### Broad (high volume, more reach)
`#markdown #writingapp #productivityapp #macos #indiedev #opensource #amwriting #productivity #writers #writingtools #appdesign #design #ux`

### Niche (lower volume, higher engagement)
`#tauri #codemirror #rustlang #mobydick #literature #typography #serif #parchment #indiehacker #microapps #foss #notesapp #digitalwriting #plaintextcommunity`

Default starter set for the first 10 posts:
`#markdown #writingapp #macos #indiedev #opensource #amwriting #productivity #writers #appdesign #tauri #codemirror #mobydick #parchment #typography #foss`

---

## Aesthetic rules

Every image (carousel slide or single post) must satisfy at least one of:

1. **Pequod palette only.** Navy (`#0D2F42` or `#0B1F2D`), parchment (`#F1E7D2`), amber (`#BD8C68` / `#D4A882`), cream (`#F7F3EE`), ink (`#1A2D3C`). Black is reserved for the cast shadow under screenshots.
2. **Set in Source Serif 4** for prose, **JetBrains Mono** for code/keyboard, **Didot italic** for the wordmark. No system-default sans-serif.
3. **No drop-shadow on text.** Subtle shadow on screenshot frames only.
4. **At least 8% safe margin** on all edges (Instagram crops aggressively in grids and Reels covers).

Carousel rules:
- 1080×1350 (4:5) for vertical impact — beats 1:1 square in the feed.
- Same template for all slides in a carousel; vary only the text and the accent.
- First slide must read in 1 second. Last slide must have a follow-up action (URL, handle, or a question).

Reels rules:
- 9:16 (1080×1920). Hook in the first 2 seconds. Keep them under 15 seconds; Instagram pushes short Reels harder than long ones.
- Captions burnt in (people scroll without sound).

---

## Tools

- **Image editing:** Figma (free), Affinity Designer, or Acorn. Set up one master frame at 1080×1350 with the palette as styles.
- **Screen capture:** built-in macOS `Cmd+Shift+5` for the editor screenshots. For a focus-mode demo Reel, the same tool records a screen video; trim in Final Cut Free or CapCut.
- **Quote graphics:** any of the above. Don't use Canva templates — they have a recognisable Canva-y aesthetic that fights the Pequod palette.

---

## Engagement playbook

- Always reply to comments in the first hour. Instagram weights early engagement.
- Like + briefly reply to every DM about the app. Each one is a future user.
- Tag adjacent accounts in the first comment, not the caption: e.g. `@iawriter`, `@obsidian.md`, `@codemirror`, `@taurihq` (if those accounts exist). They sometimes share.
- Cross-post the same image to Mastodon and Bluesky on the same day — the audiences overlap less than you'd think.
- Save Reels of the app being used; people return to them weeks later when searching for "markdown app focus mode".

---

## Posts

Drafted in `posts/`. Each `.md` file is one post — image brief, caption,
hashtag set, suggested posting window. Numbered roughly in the order you
should ship them, but reorder freely.

1. [01-launch.md](posts/01-launch.md)
2. [02-call-me-ishmael.md](posts/02-call-me-ishmael.md)
3. [03-what-is-not.md](posts/03-what-is-not.md)
4. [04-pequod-palette.md](posts/04-pequod-palette.md)
5. [05-focus-mode-reel.md](posts/05-focus-mode-reel.md)
6. [06-keyboard-pills.md](posts/06-keyboard-pills.md)
7. [07-icon-evolution.md](posts/07-icon-evolution.md)
8. [08-magic-in-it.md](posts/08-magic-in-it.md)
9. [09-electron-to-tauri.md](posts/09-electron-to-tauri.md)
10. [10-theme-switch.md](posts/10-theme-switch.md)
11. [11-built-by-one.md](posts/11-built-by-one.md)
12. [12-call-for-feedback.md](posts/12-call-for-feedback.md)
