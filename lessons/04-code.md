# Code

Markdown was made by programmers, so it is good at showing code without changing it.

## Inline code

Wrap a short piece of code, a file name, or a key in backticks: press `Ctrl+S` to save, edit `settings.json`, or call `print()`.

Backticks stop Markdown from interpreting what is inside them: `*this stays as asterisks*`.

## Code blocks

For several lines, put three backticks on the line before and the line after. Everything between is shown exactly as typed, in a monospaced font:

```
Dear diary,
    today it rained.
```

Write the language's name after the opening backticks. Loomings does not colour the code, but many tools that read Markdown will:

```python
def greet(name):
    return f"Hello, {name}!"
```

```r
x <- c(1, 2, 3)
mean(x)
```

## Why this matters

Word processors turn straight quotes into curly ones and hyphens into dashes. Code blocks protect what you paste, so a command or a formula copied from a Markdown document still works when pasted back.

## Try it

> **Exercise 1.** Write a sentence that mentions a keyboard shortcut and a file name, both in inline code.
>
> **Exercise 2.** Paste any command, formula, or address into a code block.
>
> **Exercise 3.** Add a code block in a language you know, with the language name after the backticks.
