# Citations and diagrams: design

Date: 2026-11-04. Status: for review.

## Mermaid (web only)

A fenced block with the language `mermaid` shows as a diagram in the preview, print and HTML export. The source stays in the document. Pele 1.x renders it (`pele/lazy`, MIT). `renderMarkdown` and `renderPreview` do not change, so the native HTML fixtures stay valid. The diagrams go into the DOM after the render.

A diagram that does not parse shows its source and the error as text. Links and images in diagrams are off (`links: false`, `images: false`), because a share link is untrusted text. Colours come from the palette through `--pele-*` variables.

The native app keeps the code block. Native diagrams need a colour step first: CoreSVG ignores `var()`, and the shapes came out black in the test of 2026-11-04.

## Citations (web and native)

### One source of truth

The document's frontmatter holds the choice. A selector writes to it, so a selector and hand-written YAML cannot disagree. The keys are Pandoc's, so the file also works in Pandoc and Quarto:

```yaml
---
bibliography: references.bib   # one name, or a list
csl: vancouver                 # bundled id, or a .csl file
lang: pt-PT                    # optional, default en-US
reference-section-title: Referências   # optional
---
```

Without `csl:`, the style is `chicago-author-date`, Pandoc's default. Without `bibliography:` and `references:`, Loomings treats `[@key]` as ordinary text. Either key turns citations on.

### Syntax

The Pandoc subset: `[@key]`, `[@a; @b]`, `[see @key, p. 3]`, `[-@key]` and bare `@key`. A bare key needs a non-alphanumeric character before it, so `a@b.pt` is not a citation. `\@` escapes. Code spans, code blocks and the frontmatter are skipped. `nocite:` and `::: {#refs}` are out of scope.

### Web: files stay in the browser

The user adds a `.bib` or `.csl` file with a picker or by dropping it on the page. The app reads the file locally and keeps the text in IndexedDB. Nothing goes to a server, so the "no upload" promise holds. The file is matched to the frontmatter by base name. Where the File System Access API exists, the app also keeps the handle and reads the file again on focus.

A bibliography name with no stored file gives one note with a button: "Add references.bib".

### References view

The right column of Split has two tabs: Preview and References. References lists the library with a filter. Each entry shows whether the document cites it. A click inserts `[@key]` at the caret. Cited keys with no entry are listed at the top.

### Output

The preview shows formatted citations and the reference list at the end, under `reference-section-title` if the key exists. Print and HTML export do the same. In the editor, a citation has the marker colour, an unknown key has a checker note, and `@` offers completion from the library.

### Share links

A share link always carries the cited entries, so the receiver sees the same citations with no file. The shared text gets one frontmatter line, `references: [...]`, with the cited entries as CSL JSON on one line. JSON is valid YAML, so Pandoc reads the same line, and Loomings needs no YAML library. Only the shared text has this line. The writer's document does not change. Entries in `references:` fill the library, and a `.bib` entry with the same key wins. A bundled `csl:` travels by name. An uploaded style does not travel, so the receiver gets the default style and a note. The print QR code uses the same text.

### Native

The app reads `bibliography:` and `csl:` relative to the document's folder. A References menu has Choose Bibliography…, Citation Style (bundled styles, then Choose File…) and Show References. Each choice edits the frontmatter as one undoable edit. An untitled document gets an absolute path.

### One implementation

All citation logic is in JavaScript under `src/citations/`. The web runs it in a worker. The native app runs one bundle in JavaScriptCore on its own queue. This is the first feature that does not repeat its rules in Swift. Citation work must never run on the edit path, and it must not join the teaching report, because it can take 500 ms.

## Measured on 2026-11-04

Bundle of `citeproc` and `@citation-js/plugin-bibtex`: 498 kB, 135 kB gzipped. A real 191-entry file (105 KB) parses in 49 ms in Node. A new APA engine costs about 350 ms, and 60 citations about 490 ms. It runs in JavaScriptCore without a DOM, and it decodes LaTeX accents and `@string`.

Four results shape the design:

- One bad entry makes the parser throw for the whole file, so entries must be parsed one at a time.
- A dependent style gives `[NO_PRINTED_FORM]` with no error, and most journal styles are dependent. It must be detected.
- An unknown key makes citeproc throw, so keys must be filtered first.
- `vancouver.csl` does not exist in the styles repository. The file is `nlm-citation-sequence.csl`.

## Bundled styles and locales

Styles: `chicago-author-date`, `apa`, `vancouver` (from `nlm-citation-sequence`), `american-medical-association`, `ieee`. Locales: `en-US`, `en-GB`, `pt-PT`, `es-ES`. All are CC BY-SA 3.0, so they ship with that licence and attribution.

## Licences

`citeproc` is under the CPAL or the AGPL, and Loomings is MIT. It does not ship as a separate component: the build puts it in one file with MIT code, the worker chunk `worker-*.js` on the web and `citations.js` on the Mac. Each of these files starts with a notice that names citeproc, its copyright and its licence file. The licence file ships beside the bundle (`/app/licenses/citeproc-LICENSE.txt`, `LICENSE-citeproc`), and About has the attribution. The CSL licence notice ships in the same way (`/app/licenses/CSL-LICENSE.txt`, `LICENSE-CSL.md`). Have this read by someone qualified before a public release, with one question first: does a file with both licences meet the CPAL, or must citeproc stay in a file of its own?

## Limits

- A bundled `csl: apa` means nothing to Pandoc outside Loomings, unless a file with that name exists.
- A new lesson on citations is a later step.
- On the Mac, a known citation stays plain in the editor. Only an unknown key has a mark, because rendering attributes cannot repaint laid-out text. The web gives each citation the marker colour.
- `references:` is one line of JSON. A list over more lines is not read, and a note says so.
- No time limit stops a script in JavaScriptCore. A script that does not end stops the citation queue of its window, not the editor. On the web, a print, an export or a share link restarts a worker that gives no answer in 10 s. A worker that hangs while the writer only types stays hung until one of these.
