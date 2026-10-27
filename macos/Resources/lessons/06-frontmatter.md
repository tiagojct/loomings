---
title: "Metadata and a whole document"
author: Your name
date: 2026-09-21
---

# Metadata and a whole document

## Frontmatter

The block at the very top of this file, between two lines of three hyphens, is *frontmatter*. It holds facts about the document rather than its text: a title, an author, a date, sometimes a language or a list of tags.

Markdown itself ignores it, and Loomings dims it so it stays out of the way. Tools that turn Markdown into web pages, PDFs, or slides, such as Quarto, Pandoc, and most static site generators, read it to fill in the title page and the file's properties.

The format inside is YAML: one `key: value` per line. Put values with punctuation in quotes.

## Putting it together

A complete document usually has:

1. Frontmatter with at least a title and an author.
2. One first-level heading, the title again.
3. Second-level headings for sections, third-level inside them.
4. Paragraphs, lists, quotes, code, and tables where each fits.
5. Links to sources, and images with alternative text.

## Try it

> **Exercise.** Write a one-page report on any subject you know well. Use frontmatter, at least two sections, one list, one quotation with a source, one link, and one table. Then:
>
> - use **Preview** to read it as a reader would;
> - use Export → **Print / PDF** to make a handout;
> - use Export → **Copy share link** and send the link to a friend. Everything they need is inside the link.
