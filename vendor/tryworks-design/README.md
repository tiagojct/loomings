# @tiagojct/tryworks-design

The Tryworks design. One plate system, used by tryworks.tiagojacinto.eu, subsub.tiagojacinto.eu, antedraft.tiagojacinto.eu and loomings.tiagojacinto.eu.

Two layers:

- `css/` is the CSS layer. Any page can load it, with or without 11ty.
- `11ty/` is the 11ty layer: a base layout, includes, filters and shortcodes. It sits on the CSS layer.

## Loading the CSS layer

One entry point, `css/index.css`. It imports the tokens, base, components and masthead in that order.

```html
<link rel="stylesheet" href="/assets/css/index.css">
```

The fonts are at `fonts/`, resolved from the stylesheet as `../fonts/`. Copy `css/` and `fonts/` into the site's asset directory together, or serve the package directory as-is.

A page that uses the layer needs:

- `<html lang="en-GB">` and, if it has a theme switch, `data-theme-key="<storage key>"`.
- `data-theme="light"` or `data-theme="dark"` on `<html>` when the reader has chosen; otherwise the system setting applies.
- The theme button markup and `js/design.js` if the page has a switch.
- The component markup it uses. Nothing is generated.

`js/design.js` also wires the menu button, tabs, copy buttons, table wrapping and the page contents list. Load it with `defer`. It does nothing on a page without those elements.

## Loading the 11ty layer

```js
import { designPlugin } from "@tiagojct/tryworks-design";

export default function (eleventyConfig) {
	designPlugin(eleventyConfig);
	return {
		dir: {
			input: "src",
			includes: "node_modules/@tiagojct/tryworks-design/11ty/includes",
			layouts: "node_modules/@tiagojct/tryworks-design/11ty/layouts",
		},
	};
}
```

`designPlugin` registers the filters and shortcodes and copies `css/` and `fonts/` to `assets/`. Pages set `layout: base.njk`.

Front matter the base layout reads: `title`, `description`, `lead`, `eyebrow`, `bodyClass`, `hideTitle`, `noindex`, `alt`, `altLang`, `altLabel`, `masthead`, `tool`, `contentLicense`.

Set `contentLicense: "CC BY 4.0"` for migrated Notes content. The layout adds the original-author attribution, a link to the licence, and the exception for separately credited third-party material. Pages without this value keep their existing footer.

Data files it reads: `site` (`url`, `title`, `description`, `brand`, `brandMark`, `footerAbout`, `citation`, `repo`, `favicon`), `nav` (array of `{url, label}`), `strings` (`skip`, `mainMenu`, `menu`, `theme`, `footer`, `onThisPage`), `design` (`css`, `js`, `themeKey`, `ogImage`, `preload`), and `versions` (array of strings).

Shortcodes:

| Shortcode | Use |
|---|---|
| `{% figure "src", "alt", "caption", "fig-id" %}` | A figure with a caption |
| `{% callout "note" %}…{% endcallout %}` | A callout; `note`, `tip` or `warning`; optional second argument is the title |
| `{% tabs %}{% tab "R" %}…{% endtab %}{% endtabs %}` | A tab set |
| `{% refs %}…{% endrefs %}` | The reference container |
| `{% masthead %}` | The masthead, outside the base layout |

Filters: `slugify`, `num`, `isoDate`, `monthYear`.

## The accent

`--accent` in `css/tokens.css` is the only accent property. `--accent-soft` is derived from it with `color-mix`, so it follows. Change the two `--accent` values, light and dark, and nothing else.

The package ships the Sub-Sub value, Prussian blue: `#2c5d87` light, `#86b4da` dark. Both pass 4.5:1 against the page ground.

## Tokens

Colour: `--bg`, `--surface`, `--raised`, `--text`, `--muted`, `--faint`, `--rule`, `--rule-strong`, `--accent`, `--accent-soft`, `--sap`, `--sap-soft`, `--gamboge`, `--gamboge-soft`, `--term-bg`, `--term-text`, `--term-dim`, `--term-acc`, `--term-add`, `--term-rem`.

Type: `--serif`, `--sans`, `--mono`.

Layout: `--wrap`, `--radius`.

Every token has a light and a dark value except the terminal text colours, which stay fixed on the dark terminal ground.

## Components

Base: `.wrap`, `.skip`, `.visually-hidden`, `.sc`, `.nobr`, `.runhead`, `.button`, `.button.quiet`.

Header: `.site-header`, `.header-inner`, `.brand`, `.nav`, `.header-tools`, `.tool-link`, `.theme-btn`, `.menu-btn`, `.lang-link`.

Plate: `.plate`, `.plate-mark`, `.plate-grid`, `.legend`, `.caption`, `.figs`, `.split`, `.pair`, `.prose-block`.

Page: `.page-head`, `.section`, `.band`, `.terminal`, `.needs`, `.diagram`, `.trust`.

Document: `.doc`, `.doc-header`, `.doc-body`, `.toc`, `.prose`, `.note`, `.table-wrap`, `.table-scroll`, `.copy-btn`.

Use `pre.cmd` for a copyable shell command with a prompt, or `pre.code-with-copy` for a copyable code example without a prompt. Both use the shared copy-button behaviour.

Existing `.table-wrap` and `.table-scroll` containers are reused, so a labelled keyboard-scroll region is not wrapped in a second scrolling container.

Footer: `.site-footer`, `.footer-inner`, `.footer-about`, `.cite`, `.footer-nav`, `.footer-versions`.

Shortcode output: `.callout`, `.callout-title`, `.tabs`, `.tablist`, `.tab-panel`, `.figure`.

## The masthead

`css/masthead.css` and `11ty/includes/masthead.njk`. It is off unless the page asks for it.

In 11ty, set `masthead: true` in front matter. In plain HTML, paste this above the site header and set `aria-current="page"` on the current tool:

```html
<div class="masthead">
	<div class="wrap masthead-inner">
		<p>Part of <a href="https://tryworks.tiagojacinto.eu/">Tryworks</a>, a learning hub for health researchers.</p>
		<nav aria-label="Tryworks tools">
			<ul>
				<li><a href="https://tryworks.tiagojacinto.eu/tools/sub-sub/">Sub-Sub</a></li>
				<li><a href="https://tryworks.tiagojacinto.eu/tools/antedraft/">Antedraft</a></li>
				<li><a href="https://tryworks.tiagojacinto.eu/tools/loomings/">Loomings</a></li>
			</ul>
		</nav>
	</div>
</div>
```

The strip is not sticky and does not carry analytics.

## Vendoring

The package is consumed through `file:vendor/tryworks-design`. From the tryworks repository, `npm run design:vendor` copies the package into each consumer and writes `design.sha256`. Use `npm run design:vendor -- --only=antedraft,loomings` to refresh named consumers while another phase still owns the rest. Each consumer's check script compares the hash. A mismatch fails the check.

## Accessibility

- Every colour pair meets 4.5:1 for text and 3:1 for non-text at the shipped accent.
- Focus is a 2px accent outline with a 3px offset.
- The theme button, menu button and tabs are real buttons with `aria-expanded`, `aria-selected` and arrow-key support.
- The skip link is first in the tab order.
- Motion is removed under `prefers-reduced-motion`.
- The masthead is a `nav` with a label, so it is a landmark, not a run of links.

## Demo

`npm run demo` in this package builds and serves `demo/` on port 8099. It renders every component and both masthead states.

## Licence

MIT. The fonts are SIL Open Font License 1.1: Literata, Atkinson Hyperlegible Next, Atkinson Hyperlegible Mono.
