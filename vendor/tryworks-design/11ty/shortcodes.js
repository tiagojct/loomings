import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));

function esc(value = "") {
	return String(value)
		.replace(/&/g, "&amp;")
		.replace(/</g, "&lt;")
		.replace(/>/g, "&gt;")
		.replace(/"/g, "&quot;");
}

/* The masthead, for a page that needs it outside the base layout. */
export function mastheadShortcode() {
	const source = fs.readFileSync(path.join(here, "includes/masthead.njk"), "utf8");
	return source;
}

/* {% figure "src", "alt", "caption", "fig-id" %} */
export function figureShortcode(src, alt, caption, id) {
	const idAttr = id ? ` id="${esc(id)}"` : "";
	const cap = caption ? `<figcaption>${esc(caption)}</figcaption>` : "";
	return `<figure class="figure"${idAttr}><img src="${esc(src)}" alt="${esc(alt)}" loading="lazy">${cap}</figure>`;
}

/* {% callout "note", "Title" %}...{% endcallout %} */
export function calloutShortcode(content, type = "note", title = "") {
	const kind = ["note", "tip", "warning"].includes(type) ? type : "note";
	const head = title ? `<p class="callout-title">${esc(title)}</p>` : "";
	return `<div class="callout callout-${kind}" role="note">${head}${content}</div>`;
}

/* {% tabs %}{% tab "R" %}...{% endtab %}{% endtabs %} */
export function tabShortcode(content, label = "") {
	return `<div class="tab-panel" data-label="${esc(label)}" role="tabpanel" hidden>${content}</div>`;
}

export function tabsShortcode(content) {
	const panels = content.match(/<div class="tab-panel" data-label="([^"]*)"[^>]*>[\s\S]*?<\/div>/g) || [];
	if (!panels.length) return `<div class="tabs">${content}</div>`;
	const labels = panels.map((p) => (p.match(/data-label="([^"]*)"/) || [])[1] || "");
	const id = `tabs-${Math.random().toString(36).slice(2, 8)}`;
	const buttons = labels
		.map((label, i) => `<button type="button" role="tab" id="${id}-t${i}" aria-controls="${id}-p${i}" aria-selected="${i === 0}" tabindex="${i === 0 ? 0 : -1}">${esc(label)}</button>`)
		.join("");
	const bodies = panels
		.map((panel, i) => panel.replace("<div ", `<div id="${id}-p${i}" aria-labelledby="${id}-t${i}" `).replace(" hidden", i === 0 ? "" : " hidden"))
		.join("");
	return `<div class="tabs" data-tabs><div class="tablist" role="tablist">${buttons}</div>${bodies}</div>`;
}

/* {% refs %}...{% endrefs %}: a container a build transform fills. */
export function refsShortcode(content = "") {
	return `<div id="refs" class="refs">${content}</div>`;
}

export function registerShortcodes(eleventyConfig) {
	eleventyConfig.addShortcode("masthead", mastheadShortcode);
	eleventyConfig.addShortcode("figure", figureShortcode);
	eleventyConfig.addPairedShortcode("callout", calloutShortcode);
	eleventyConfig.addPairedShortcode("tab", tabShortcode);
	eleventyConfig.addPairedShortcode("tabs", tabsShortcode);
	eleventyConfig.addPairedShortcode("refs", refsShortcode);
}
