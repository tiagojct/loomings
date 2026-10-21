# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

Two audiences told as one story:

- **Writers at a desk** — someone with a draft to finish, who wants a real
  editor that gets out of the way and does not ask for an account.
- **Teachers and students** — a teacher preparing a Markdown lesson, or
  handing a document to a class; students opening what they were sent.

The primary decision-maker the landing page must convince is the teacher: the
page succeeds when a teacher decides to use Loomings with a class.

## Product Purpose

A Markdown editor that runs entirely in the browser. It exists so that writing
and handing writing to other people needs no account, no upload and no server.
Success is a teacher running a lesson from it, or a writer finishing a draft in
it, without either of them thinking about the tool.

## Positioning

The whole document can travel inside a URL fragment: a share link carries the
text itself, compressed, and the fragment never reaches a server. Combined with
in-place Markdown rendering (bold reads bold, headings read as headings) and no
backend at all, this is a mechanism a cloud editor cannot truthfully copy
without giving up the property that makes it work.

## Operating Context

- Classroom use: a teacher shows Markdown source beside its rendered result,
  hands out a link, and receives work back as a link or a PDF.
- The bundled lessons are written to demonstrate themselves — syntax on one
  side, result on the other, an exercise at the end.
- Documents live in one of three places: a file on disk (File System Access
  API, Chromium), a document in the browser's own storage (IndexedDB), or
  nothing yet (untitled buffer). Crash recovery keeps an unsaved draft in
  IndexedDB and offers it back on the next visit.
- Installed as a PWA it works offline and can open `.md` files from the OS.

## Capabilities and Constraints

- Static site, no backend, no accounts, no tracking in the app; the landing
  page alone loads one analytics script (umami).
- Colours come from four palettes (Pequod, Glauca, Try-Works, Ambergris), each
  with a dark and a light mode; a light/dark/system theme and eight looks in
  total. Palettes are WCAG-checked by the test suite.
- Features: in-place Markdown rendering, split view with scroll sync, outline
  palette, focus mode, typewriter scrolling, full screen, word goal, stats,
  find and replace, six bundled lessons, cheatsheet, print/PDF, standalone
  HTML export, share links, offline install.
- Deployed as a container behind Cloudflare and Caddy at
  `loomings.tiagojacinto.eu`; the app lives at `/app/`, the landing page owns
  the root. CSP is strict and self-only, so the landing page cannot fetch
  third-party fonts or images.
- Source is MIT licensed at `github.com/tiagojct/loomings`.

## Brand Commitments

- The name **Loomings** is the first chapter of *Moby-Dick*; the literary
  register and the nautical naming of the palettes are deliberate.
- Voice: understated, literate, slightly old-fashioned; never salesy, never
  cute. English.
- The author is Tiago Jacinto; the site is his own, not a company's.

## Evidence on Hand

- The product itself: the full editor is public and can be linked to directly.
- A bundled first chapter of *Moby-Dick* as the demo document, and six
  self-demonstrating lessons.
- Real screenshots of the running app in `docs/assets/screenshot.png`
  (2800×1800) and `docs/assets/og.png` (1200×630), both capturable again from
  the current build.
- Source code and the MIT licence.
- **Absences that must not be fabricated:** no testimonials, no user numbers,
  no logos of institutions, no press, no pricing, no roadmap promises. The
  page may say the app is free, open source and needs no account because all
  three are true.

## Product Principles

1. **Nothing you type leaves the machine unless you make it a link.** Privacy
   is a mechanism here, not a policy page.
2. **Show the source and the result together.** Teaching and writing are the
   same act of seeing what the markup becomes.
3. **The tool recedes.** No accounts, no dialogs before the first word, no
   assistant in the margin.
4. **Everything the page claims, the product demonstrates.** No feature is
   described that the visitor cannot try one click away.
5. **The work travels lightly.** A document is a file, a link, or a printout —
   never a hostage.

## Accessibility & Inclusion

- The app's palettes are tested against WCAG contrast floors; the landing page
  has no such test and should meet the same standard.
- The app is used in classrooms, including on projectors and shared screens:
  text must stay legible at distance and the page must work without motion.
