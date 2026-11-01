# Teaching features: spec

Ten features that make Loomings a teaching editor, built in the native macOS
app first (`macos/`), then ported to the web app (features 1, 2, 3, 4, 6, 8,
9). Decided with the owner on 2026-11-01.

## Decisions

- Native first, web port second. The web port is a separate plan, written
  after the native work lands, and shares the rule definitions and test
  fixtures below.
- Process replay history is opt-in per document and lives in
  `~/Library/Application Support/Loomings/History/`. It never goes next to
  the file and never into a share link. Delete History removes it.
- Send to the room uses AirDrop through the system sharing service.
- Compare With works against any open document.

## The ten features

1. Paired lines. In Split view, the pointer over a source line highlights the
   preview block made from it; the pointer over a preview block highlights
   its source lines.
2. Learner's checker. Notes on common Markdown mistakes, each with the reason
   and, where safe, a one-click fix. Rules (ids are shared with the web port):
   - `heading-space`: `#Title` at a line start is not a heading. Fix: insert a space.
   - `accidental-setext`: a line of hyphens under a paragraph turns it into a
     heading. Flagged when the heading text spans more than one line or ends
     with `.`, `,`, `;` or `:`. Fix: insert a blank line above the hyphens.
   - `unclosed-fence`: a fenced code block that runs to the end of the
     document. Fix: append the closing fence.
   - `ordered-list-interrupt`: `N. text` with N other than 1 directly under a
     paragraph line stays part of the paragraph. Fix: insert a blank line.
   - `link-space`: `[text](a b)` is not a link. Fix: wrap the address in `<>`.
   - `image-alt`: `![](src)` has no alternative text. No fix.
   - `unpaired-emphasis`: `**` or `__` left over as literal text. No fix.
   - `table-separator`: two or more consecutive paragraph lines that start
     and end with `|`, with no separator row. Fix: insert `| --- |` cells
     after the first line, one per column.
3. Explain this marker. Option-click a Markdown marker in the editor to see
   what it does and which lesson teaches it.
4. Exercises that check themselves. A document's frontmatter lists checks;
   Loomings evaluates them locally and shows which pass. Bundled lessons get
   their checks from `lessons/checks.json`, so the lesson files stay
   unchanged. Directive syntax, one per line inside the frontmatter:
   `check: <kind> [arguments]`. Kinds: `heading [level] [min]`,
   `bullet-list [items]`, `ordered-list [items]`, `nested-list`, `quote`,
   `code-block [language]`, `code-language` (a fenced block with any
   language name), `inline-code [min]`, `link [min]`,
   `reference-link`, `image-alt`, `table [rows]`, `emphasis`, `strong`,
   `words [min]`. Checks attached to a bundled lesson look only at what
   follows the lesson's original text, so the lesson's own examples never
   count as the answer; they are not saved with the file.
5. Hand-in and compare. File > Compare With... opens a window with the front
   document beside another open document, line differences marked, word
   differences marked inside changed lines.
6. Classroom projector mode. One command: large type in editor and preview,
   chrome hidden, the current line marked, and a short overlay that names the
   markup or shortcut just used. Turning it off restores the previous state.
7. Process replay. Opt-in recording of a document's edits; a replay window
   plays the writing back with a slider and speeds.
8. Handout PDF. A paginated PDF with page numbers, the light palette of the
   current family, and a QR code holding the share link when the link fits
   in a QR code (at most 2,900 bytes). The share tool also shows the QR code.
9. Section word limits. Frontmatter directive `limit: <heading title> <max>`;
   the status bar shows the caret's section count against its limit, and the
   outline lists each section's count.
10. Send to the room. Share > Send with AirDrop sends the document as a `.md`
    file.

## Constraints

- macOS 15+, Apple Silicon, Swift tools 6.0, Swift language mode 5.
- No new package dependencies. No network requests.
- Colours come only from the resolved Ensigns palette (system colours when
  there is none).
- UI copy in English, British spelling as in the lessons ("colour", "centre").
- Typing must never wait for the checker, checks, limits or history.
- One commit per feature. No Claude author or co-author lines.
