# render-doc.py

Build tool that renders the project's Markdown documents to styled,
self-contained **HTML** and a plain-text **ASCII** version. It is a
development/build helper -- it is **not** needed at runtime by fetchconfig-web
itself. It absorbs the former `render-changes.py`: there is now one renderer for
every document.

## Usage

```sh
python render-doc.py [input.md] [output.html]
```

The **script name comes first**. A common mistake is to omit it, e.g.
`python INSTALL.md INSTALL.html` -- that asks Python to execute the Markdown and
fails with a `SyntaxError`. Always run `python render-doc.py <input> <output>`.

For a Markdown input it writes **two** files:

- the HTML page (`output.html`), and
- an **ASCII** plain-text rendering, named after the input with the
  `.md`/`.markdown` suffix stripped (an input without one of those suffixes gets
  `.txt` appended instead, so the source is never overwritten).

The one exception is the **license** style below: a `LICENSE` input writes the
HTML and a `.md`, and no plain-text file -- the input already *is* plain text.

Output names: the HTML argument is optional and defaults from the input --
`README.md` keeps its historical name `fetchconfig-web-documentation.html`, and
any other `X.md` defaults to `X.html`. The ASCII name is the input without `.md`:

| Input | HTML | ASCII |
|-------|------|-------|
| `README.md` | `fetchconfig-web-documentation.html` | `README` |
| `INSTALL.md` | `INSTALL.html` | `INSTALL` |
| `CHANGES.md` | `CHANGES.html` | `CHANGES` |
| `DEVELOPER.md` | `DEVELOPER.html` | `DEVELOPER` |
| `LICENSE-ADDITIONS.md` | `LICENSE-ADDITIONS.html` | `LICENSE-ADDITIONS` |
| `PRIVACY.md` | `PRIVACY.html` | `PRIVACY` |
| `README.imageconvert.md` | `README.imageconvert.html` | `README.imageconvert` |

Run it from the project directory after editing a document:

```sh
python3 render-doc.py                          # README.md -> manual + README
python3 render-doc.py INSTALL.md               # -> INSTALL.html + INSTALL
python3 render-doc.py CHANGES.md               # -> CHANGES.html + CHANGES
python3 render-doc.py DEVELOPER.md             # -> DEVELOPER.html + DEVELOPER
python3 render-doc.py README.imageconvert.md   # -> .html + README.imageconvert
```

## Styles (chosen automatically)

- **manual** -- the full sidebar/hero manual, used for **every** Markdown
  document (README, INSTALL, CHANGES, DEVELOPER, LICENSE-ADDITIONS, PRIVACY,
  and any other `.md`). The hero shows a single turquoise (`--accent`) `<h1>`
  built from the H1 as `fetchconfig-web &mdash; <Subtitle>` (a bare
  `fetchconfig-web` H1 falls back to "Documentation"), followed by the lede; the
  sidebar is built from the `##` sections and their `###` subsections, each
  section carrying a numbered kicker. A document whose H1 starts with
  `fetchconfig-web` is treated as an *app document* and additionally gets the app
  version/stat tiles; any other document (e.g. `README.imageconvert.md`) gets a
  clean hero titled from its own H1 (`<Program> &mdash; <Subtitle>`). The
  fetchconfig-specific **warning callouts** are narrower still: they are emitted
  only for `README.md` and `INSTALL.md`, the two operational documents, so the
  changelog, developer and legal pages do not carry runtime warnings.
  A ```` ```mermaid ```` fenced block is rendered as a diagram (DEVELOPER.md);
  the Mermaid runtime is loaded from a CDN **only** on pages that contain one.
- **license** -- a verbatim `<pre>` of a `LICENSE` file; the legal text is
  reproduced exactly and is not reflowed, under the same turquoise
  `fetchconfig-web &mdash; <title>` heading. `render-doc.py LICENSE LICENSE.html`
  also writes `LICENSE.md` (the text in a fenced block), and writes no plain-text
  file. Note the selector is broad: this style is chosen for a basename starting
  `LICENSE` with no dot **or for any input whose name does not end in `.md`,
  `.markdown`, `.html` or `.htm`** -- so an extensionless input is always treated
  as a license.

## Markdown it understands

Top-level `##` headings (sections), `###`/`####` sub-headings, GitHub-style pipe
tables, fenced code blocks, ordered/unordered lists (with wrapped continuation
lines), blockquote callouts, and inline code / bold / italic / links. A
blockquote whose first line is a GitHub alert marker (`> [!CAUTION]`,
`> [!WARNING]`) renders as a red warning callout; `[!NOTE]`, `[!TIP]`,
`[!IMPORTANT]` or no marker render as the normal note callout.

Two behaviours worth knowing when editing a document:

- **Diagram / ASCII twins.** A ```` ```text ```` fence placed immediately after a
  ```` ```mermaid ```` fence is treated as that diagram's plain-text twin: the
  HTML shows only the rendered diagram (the text block is dropped), and the ASCII
  rendering shows only the text block (the mermaid source is dropped). This is how
  DEVELOPER.md carries both a diagram and a readable ASCII flow without either
  output showing the same thing twice. Keep the two fences adjacent, and keep them
  saying the same thing.
- **Horizontal rules.** A line of `---`, `***` or `___` on its own is a thematic
  break: an 80-column rule in the ASCII output and an `<hr>` in the HTML. A pipe
  table's separator row is never mistaken for one (it always contains `|`), and
  the rule that follows a document's lede is absorbed into the hero rather than
  emitted twice.

The ASCII renderer wraps prose to 80 columns, underlines headings, renders pipe
tables as aligned columns (falling back to one `Header: value` record per row
when a table is too wide to fit), keeps fenced code verbatim (indented), indents
blockquotes, and strips inline markup and common HTML entities.

The HTML version/stat values (sidebar pill, hero tile, the "requires
fetchconfig" warning) are read from the `APP_VERSION_INTERNAL` and
`MIN_FETCHCONFIG_VERSION` constants in `fetchconfig-web.cgi` (same directory as
`render-doc.py`), so they cannot drift from the code; `?` is shown with a stderr
warning if the file or a constant is missing.

## Requirements

- Standard library only (`sys`, `re`, `io`, `os`, `textwrap`, and `html`/`cgi`);
  no third-party packages.
- Runs unchanged on **Python 3 and Python 2.7.18**.

The embedded stylesheet means the generated HTML has no external assets other
than Google Fonts -- and, on a document that uses a ```` ```mermaid ```` block,
the Mermaid runtime (loaded from `cdn.jsdelivr.net` only for those pages). The
script needs no companion files. The HTML output itself is 7-bit ASCII
(typography is emitted as HTML entities); the generated plain-text file is UTF-8.
