# Tables, rules and escaping

## Tables

A table is rows of cells separated by vertical bars. The second row, made of hyphens, separates the header from the body:

| Term | Meaning |
| --- | --- |
| Heading | A title for a section |
| Emphasis | Text that carries weight |
| Block | A paragraph, list, quote, or code |

Colons in the separator row align the column: `:---` left, `:---:` centre, `---:` right.

| Item | Quantity | Price |
| :--- | :---: | ---: |
| Coffee | 2 | 3.40 |
| Bread | 1 | 1.20 |

The bars do not need to line up in the source. They only need to be there.

## Horizontal rules

Three or more hyphens, asterisks, or underscores on a line of their own draw a rule across the page, for a change of scene:

---

## Escaping

When you need a character that Markdown would otherwise interpret, put a backslash before it: \*not emphasis\*, 3 \* 4, a \# that is not a heading.

## Try it

> **Exercise 1.** Make a table with three columns: a course you are taking, its teacher, and the day of the week it meets. Add three rows.
>
> **Exercise 2.** Right-align one column of your table.
>
> **Exercise 3.** Write a sentence that contains a literal asterisk and a literal underscore, escaped so they show as themselves.
