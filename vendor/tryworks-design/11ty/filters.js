/* Filters shared by the sites. */

export function slugify(text) {
	return String(text)
		.normalize("NFKD")
		.replace(/[\u0300-\u036f]/g, "")
		.replace(/['\u2019\u2013\u2014]/g, "")
		.toLowerCase()
		.replace(/[^a-z0-9]+/g, "-")
		.replace(/^-+|-+$/g, "");
}

export function num(value, decimals = 1) {
	if (value === null || value === undefined || value === "") return "";
	const n = Number(value);
	if (Number.isNaN(n)) return "";
	return n.toFixed(decimals);
}

export function isoDate(value) {
	if (!value) return "";
	return new Date(value).toISOString().slice(0, 10);
}

export function monthYear(value, locale = "en-GB") {
	if (!value) return "";
	return new Intl.DateTimeFormat(locale, { month: "long", year: "numeric" }).format(new Date(value));
}

export function registerFilters(eleventyConfig) {
	eleventyConfig.addFilter("slugify", slugify);
	eleventyConfig.addFilter("num", num);
	eleventyConfig.addFilter("isoDate", isoDate);
	eleventyConfig.addFilter("monthYear", monthYear);
}
