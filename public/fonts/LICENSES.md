# Fonts

These files are served with the app (`/app/fonts/…`) because the CSP only
allows same-origin fonts. All three families are under the SIL Open Font
License 1.1; the licence text for each — including its copyright line — is
next to this file.

| File | Family | Style | Subset | Source |
| --- | --- | --- | --- | --- |
| `atkinson-hyperlegible-400.woff2` | Atkinson Hyperlegible | regular | latin | Google Fonts (`fonts.gstatic.com`) |
| `atkinson-hyperlegible-400-italic.woff2` | Atkinson Hyperlegible | italic | latin | Google Fonts (`fonts.gstatic.com`) |
| `atkinson-hyperlegible-700.woff2` | Atkinson Hyperlegible | bold | latin | Google Fonts (`fonts.gstatic.com`) |
| `jetbrains-mono-400.woff2` | JetBrains Mono | regular | latin | Google Fonts (`fonts.gstatic.com`) |
| `source-serif-4-400.woff2` | Source Serif 4 | regular (optical 8–60) | latin | Google Fonts (`fonts.gstatic.com`) |
| `source-serif-4-400-italic.woff2` | Source Serif 4 | italic (optical 8–60) | latin | Google Fonts (`fonts.gstatic.com`) |

Retrieved 2026-10-21 from the Google Fonts CSS API with a desktop Chrome
user agent, which serves the woff2 latin subset of each face. The
`unicode-range` values in `src/fonts.css` are the ones the API returned, so a
browser only downloads a face when the document uses those code points.

Bold weights that are not listed here (Source Serif 4 bold, JetBrains Mono
bold) are synthesised by the browser rather than shipped: the genuine
Source Serif 4 bold file is 119 kB on its own, which is not worth it for
`<strong>` in a preview pane.

To refresh: fetch the same CSS API URLs, replace the `.woff2` files, and keep
the `unicode-range` lines in `src/fonts.css` in sync with the response.
