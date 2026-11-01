import anchor from "markdown-it-anchor";
import { slugify } from "./filters.js";
import { registerFilters } from "./filters.js";
import { registerShortcodes } from "./shortcodes.js";

/* Register both layers on an Eleventy config. The consumer still sets
   dir.includes to this package's 11ty/includes and dir.layouts to its
   layouts, or copies them. */
export function designPlugin(eleventyConfig) {
	registerFilters(eleventyConfig);
	registerShortcodes(eleventyConfig);
	eleventyConfig.amendLibrary("md", (md) =>
		md.use(anchor, {
			slugify,
			level: [2, 3],
			permalink: anchor.permalink.linkInsideHeader({ symbol: "#", placement: "after" }),
		}),
	);
	eleventyConfig.addPassthroughCopy({ "node_modules/@tiagojct/tryworks-design/fonts": "assets/fonts" });
	eleventyConfig.addPassthroughCopy({ "node_modules/@tiagojct/tryworks-design/css": "assets/css" });
	eleventyConfig.addPassthroughCopy({ "node_modules/@tiagojct/tryworks-design/js": "assets/js" });
}

export { registerFilters, registerShortcodes };
