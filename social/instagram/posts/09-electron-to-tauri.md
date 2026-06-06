# 09 — Electron → Tauri

**Format:** carousel, 4 slides, 1080×1350
**Pillar:** the making of
**Best slot:** week 4 Thursday (developer audience overlaps with end-of-week reading)

## Slides

### Slide 1 — Hook
- Background: navy.
- Center: a big number, `180 MB`, in italic Source Serif Display, 220 pt, cream, struck through with an amber line.
- Below: a smaller number, `12 MB`, in italic Source Serif Display, 220 pt, amber.
- Below: "the same writing app." in regular Source Serif, 32 pt, muted cream.

### Slide 2 — Why
- Background: parchment.
- Three-line block, left-aligned, italic Source Serif, 40 pt:
  - Electron bundles a full Chromium.
  - Tauri uses the OS web view.
  - Loomings has no reason to ship a browser.
- Bottom: `tiagojct.eu/loomings`.

### Slide 3 — Numbers
- Background: navy.
- Centered table-like layout, two columns, JetBrains Mono, 32 pt cream:
  | metric        | electron | tauri |
  |---------------|---------:|------:|
  | binary        |   180 MB |  12 MB |
  | idle RAM      |   150 MB |  30 MB |
  | cold start    |    1.8 s |  0.4 s |
  | rust backend  |       no |   yes |
- Below the table: thin amber rule, then "loomings v1.0.0" in italic Source Serif, 26 pt, muted cream.

### Slide 4 — CTA
- Background: parchment.
- Centered: *"Tauri 2. CodeMirror 6. About twelve megabytes."* in italic Source Serif, 56 pt.
- Below: "open source · MIT · tiagojct.eu/loomings".

## Caption

the previous prototype was electron. it worked. it was 180 megabytes and idled at 150 of RAM, which feels rude for a markdown editor.

loomings is the second rewrite. tauri 2 for the shell (rust + system web view), codemirror 6 for the editor, markdown-it for the preview, no bundled chromium. about twelve megabytes. thirty of idle RAM. roughly fifteen times lighter.

a small app should be a small app. that is the entire pitch.

## Hashtags

#tauri #rustlang #electron #appdev #indiedev #softwaredevelopment #performance #optimization #opensource #foss #rust #webdev #devlife #softwareengineering
