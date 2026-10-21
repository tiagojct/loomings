---
name: Loomings
description: A markdown editor for writing and teaching, landing page as one transparency on a classroom overhead projector.
colors:
  # Ensigns, family Pequod (ensigns.tiagojacinto.eu). Dark roles for the room
  # and the machine, light roles for the plate and the stock, ahab as accent.
  room: "#0b1720"
  machine: "#0c222f"
  machine-high: "#0d2f42"
  edge: "#163f54"
  steel: "#bfbbb6"
  steel-dim: "#a16e50"
  plate: "#f7f3ee"
  plate-deep: "#eae1d7"
  ink: "#0d2f42"
  ink-soft: "#335260"
  grease: "#931432"
  grease-glow: "#e3877c"
  paper: "#eae1d7"
  paper-deep: "#dbc9b6"
  paper-dim: "#835a49"
  rule: "#cfad8e"
  focus: "#bd8c68"
typography:
  display:
    fontFamily: "Source Serif 4, Iowan Old Style, Georgia, serif"
    fontSize: "clamp(42px, 4.4vw, 68px)"
    fontWeight: 600
    lineHeight: 1
    letterSpacing: "-0.02em"
  heading:
    fontFamily: "Source Serif 4, Iowan Old Style, Georgia, serif"
    fontSize: "clamp(31px, 3.4vw, 47px)"
    fontWeight: 400
    lineHeight: 1.18
    letterSpacing: "-0.015em"
  body:
    fontFamily: "Source Serif 4, Iowan Old Style, Georgia, serif"
    fontSize: "19px"
    fontWeight: 400
    lineHeight: 1.65
  lede:
    fontFamily: "Source Serif 4, Iowan Old Style, Georgia, serif"
    fontSize: "clamp(19px, 1.65vw, 25px)"
    fontWeight: 400
    lineHeight: 1.52
  mono:
    fontFamily: "JetBrains Mono, SF Mono, Menlo, monospace"
    fontSize: "clamp(13px, 1.12vw, 15.5px)"
    fontWeight: 400
    lineHeight: 2.05
  label:
    fontFamily: "Barlow Condensed, Oswald, Arial Narrow, sans-serif"
    fontSize: "11.5px"
    fontWeight: 600
    lineHeight: 1.4
    letterSpacing: "0.24em"
  hand:
    fontFamily: "Caveat, Bradley Hand, cursive"
    fontSize: "27px"
    fontWeight: 400
    lineHeight: 1.1
  note:
    fontFamily: "Source Serif 4, Iowan Old Style, Georgia, serif"
    fontSize: "16.5px"
    fontWeight: 400
    lineHeight: 1.55
  small:
    fontFamily: "Source Serif 4, Iowan Old Style, Georgia, serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.5
  subhead:
    fontFamily: "Source Serif 4, Iowan Old Style, Georgia, serif"
    fontSize: "22px"
    fontWeight: 600
    lineHeight: 1.3
rounded:
  sheet: "2px"
  plate: "3px"
  lamp: "4px"
  switch: "6px"
  clip: "8px"
spacing:
  xs: "8px"
  sm: "14px"
  md: "22px"
  lg: "34px"
  xl: "54px"
  section: "88px"
components:
  lamp-switch:
    backgroundColor: "{colors.machine}"
    textColor: "#f2f5f1"
    typography: "{typography.label}"
    rounded: "{rounded.switch}"
    padding: "17px 34px 17px 22px"
  ticket:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.paper-ink}"
    typography: "{typography.body}"
    rounded: "{rounded.sheet}"
    padding: "13px 16px 15px"
  tape:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.paper-ink}"
    typography: "{typography.mono}"
    rounded: "{rounded.sheet}"
    padding: "22px 26px 24px"
  binding:
    backgroundColor: "{colors.room}"
    textColor: "{colors.plate}"
    typography: "{typography.label}"
    rounded: "{rounded.sheet}"
  docket:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.paper-ink}"
    typography: "{typography.body}"
    rounded: "{rounded.sheet}"
    padding: "20px 20px 22px"
---

# Design System: Loomings

## Overview

**Creative North Star: "The Transparency on the Glass"**

The landing page is the classroom overhead projector the product belongs to: a charcoal machine holding a lit acetate sheet. That sheet carries the page's content, and it carries the product's one claim in the same gesture — Markdown on the left, what it becomes on the right, one red grease pencil, one switch. The room around it is dark because that is what makes the sheet read as light rather than as a white card.

The world is not a costume: there is no drawn projector arm, no stock illustration, no browser mockup. The machine is three surfaces (head, plate, base), the paper is paper, and the only ornament is the fresnel ring pressed faintly into the plate.

**Key Characteristics:**

- One lit field carries the page; everything else recedes into the room.
- The product demonstrates itself: source and result are the same sheet, paired line by line.
- One accent, used as a tool: a grease pencil for the switch's lamp, the paired line, and one hand-written note.
- Materials are paper, acetate, steel and light — never glass, gradient text, or illustrated chrome.
- Type does the talking: the app's own serif, mono and condensed labels, plus a single hand.

## Colors

Every colour on the page is a role from **Ensigns**, family **Pequod** (ensigns.tiagojacinto.eu): the dark roles build the room and the machine, the light roles the lit plate and the stock, and `ahab` is the one accent. No hex is invented here; when the system changes, the page follows.

### Primary

- **Ahab** (`#931432`, light; `#e3877c` on dark): the grease pencil. The switch lamp, the paired-line rule, the hand note, the one state mark. On parchment it clears 8:1.

### Neutral

- **Room** (`#0b1720`): the dark the sheet is lit against; the page background, and the close band.
- **Machine** (`#0c222f`, high `#0d2f42`, seam `#163f54`): the head, base and switch bodies; the machine is a raised navy surface on the room.
- **Steel** (`#bfbbb6`) and **Steel Dim** (`#a16e50`): body text and quiet labels on the room; the warm subtle, never a second accent.
- **Plate** (`#f7f3ee`, deep `#eae1d7`): the lit sheet, in the family's brightest parchment. **Ink** (`#0d2f42`) and **Ink Soft** (`#335260`) are everything written on it.
- **Stock** (`#eae1d7`, deep `#dbc9b6`, dim `#835a49`, rule `#cfad8e`): tickets, tape, the lesson sheet and the dockets — the same parchment as the plate's deep end, deliberately a step quieter.

### Named Rules

**The One Sheet Rule.** Only one surface in any viewport is lit. A second pale field is stock and must read as paper on a desk, not as another screen.

**The One Mark Rule.** Ahab is state and action, never decoration. If a red element does not mean "press this" or "this line is paired", it is wrong.

**The Ensigns Rule.** A colour that is not a role of Ensigns Pequod does not appear on this page. The ten family cards are the one exception: each carries its own family's own tokens, because that is what they demonstrate.

## Typography

Four voices, each with a job: Source Serif 4 for the written word (the same face the app renders Markdown in), JetBrains Mono for the source (the app's editor face), Barlow Condensed for the machine's silkscreened labels, Caveat for the single grease-pencil note.

### Hierarchy

- **Display** (600, `clamp(42px, 4.4vw, 68px)`, 1): the rendered document's own heading on the plate.
- **Heading** (400, `clamp(31px, 3.4vw, 47px)`, 1.18): section statements. Italic marks the phrase that carries the idea.
- **Body** (400, 19px, 1.65, measure 62ch): the page's prose, in a softened plate tone on the room.
- **Label** (600, 11.5px, 0.24em, uppercase): pane labels, claims, mode names, stamps. Never body copy.
- **Mono** (400, ~15px, 2.05): Markdown source and addresses, with `#`, `*`, `**` in grease.
- **Hand** (400, 27px): one note per page, maximum.

### Named Rules

**The Source Is Set As Source Rule.** Markdown is never prettified into prose on the left: it stays monospace, keeps its markers, and the markers are the only coloured glyphs.

## Layout

The page is a machine head (wordmark, four links), then the console (lit plate over a base), then sections on the room floor, then the close. Content measure is 1180px, gutters `clamp(20px, 4vw, 56px)`.

- The plate is a two-pane grid at desktop (source | 1px divider | result), stacking below 1024px with the divider replaced by a hairline.
- The base is a three-part panel: the offer and its claims, the lamp switch, the provenance ticket.
- Sections alternate their composition: two columns (write), a full-width lesson sheet, a full-width row of four bindings, three dockets. One vertical rhythm, `clamp(54px, 7vw, 88px)` between sections.
- Below 760px: the plate stacks, the base becomes one column with the switch before the ticket, the bindings go two-up, the dockets stack.
- Below 420px: type and controls step down; the switch stays inside the first screen.

## Elevation & Depth

Depth is light, not shadow noise: the plate glows onto the machine (a soft cool halo), paper sits on the room with a single long shadow, and the switch is lit from within.

- **Plate halo:** `0 0 80px 18px rgba(224,235,216,.13)`, plus `0 26px 60px rgba(0,0,0,.5)` to seat it.
- **Paper on the floor:** `0 18px 40px rgba(0,0,0,.4)`; the lesson sheet `0 24px 54px rgba(0,0,0,.45)`.
- **Switch:** `0 2px 0 #090c0d` (a physical lip) and `0 14px 30px rgba(0,0,0,.45)`; on hover, a warm `0 0 34px rgba(192,57,43,.28)` from the lamp.
- **Bindings:** one long shadow, a slight rotation each; hover lifts the sheet and removes the tilt.

## Shapes

Sheets are cut paper: 2px radii, straight edges, one corner clipped on the dockets. The plate is 3px; the switch is a 6px machined block. Tape is a translucent strip with a soft edge; the ticket has a drawn clip. Nothing is pill-shaped, nothing is glassy.

## Components

- **Lamp switch** — the page's only button: a charcoal block with a red rocker lamp and a condensed caps label. Links to `/app/`. Hover and focus light the lamp.
- **Ticket** — the provenance card, clipped to the machine's base: a paper slip with a clip, a label in paper-dim, and a sentence naming what the demonstration is.
- **Tape** — the share link as a strip of perforated stock, with a stamped "No upload" in grease on paper.
- **Lesson sheet** — two panes of one document on paper, a red tab ("Lesson 1 of 6") and a strip of tape; the source and the result must always be the same exercise.
- **Binding** — a palette sample: one sheet split diagonally between its dark and light side, name on the dark, mode names on the light, the same sentence in the accent.
- **Docket** — one storage truth per paper slip (on disk, in this browser, in a link), with its technical note in mono.

## Do's and Don'ts

- **Do** keep the pairing interaction (point or tap a line; its counterpart lights) as the page's only authored motion.
- **Do** let the product's own text be the hero; the page's strongest typography is rendered Markdown.
- **Do** keep red for action and state only.
- **Do** keep every demonstrated detail true to the product: the abridged chapter, the real lesson, the real palette names.
- **Don't** draw the projector as an illustration, add a browser mockup, or illustrate the Moby-Dick reference with nautical props.
- **Don't** use cream-plus-serif as the page's ground, gradient text, glass panels, generated grain, or an eyebrow label above a heading.
- **Don't** let paper become a second screen: paper is stock, plate is light.
- **Don't** add a second accent or a second hand-written voice.
