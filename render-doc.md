# render-doc.py

Build tool that renders the project's Markdown documents to styled,
self-contained HTML: `README.md` becomes `fetchconfig-web-documentation.html`
(the manual) and `INSTALL.md` becomes `INSTALL.html` (the
installation guide). It is a development/build helper -- it is **not** needed
at runtime by fetchconfig-web itself.

## Usage

```sh
python3 render-doc.py [input-markdown] [output-html]
```

The **script name comes first**. A common mistake is to omit it, e.g.
`python INSTALL.md INSTALL.html` -- that asks Python to execute the Markdown
and fails with a `SyntaxError`. Always run `python render-doc.py <input> <output>`.

Both arguments are optional and default to:

- input:  `README.md`
- output: `fetchconfig-web-documentation.html`

Run it from the project directory after editing either document:

```sh
python3 render-doc.py                                      # README.md -> manual
python3 render-doc.py INSTALL.md INSTALL.html   # install guide
```

The page title, hero eyebrow and lede are derived from the input: the H1
`fetchconfig-web -- <Subtitle>` supplies the eyebrow/title (a bare
`fetchconfig-web` H1 falls back to "Documentation") and the first intro
paragraph after the H1 is the lede. The sidebar is built from the `##`
sections and their `###` subsections, so both documents stay in sync with
their Markdown automatically.

## Requirements

- Python 3 or Python 2.7 (standard library only -- `sys`, `re`, `io`, and
  `html`/`cgi`; no third-party packages).
- Runs unchanged on both Python 3 and Python 2.7.18.
  packages).

## What it does

It converts the README's Markdown into a single, self-contained HTML page in
the same visual style as the upstream `fetchconfig-documentation.html`:

- Top-level `##` headings become numbered sections; `###`/`####` become
  sub-headings.
- GitHub-style pipe tables, fenced code blocks, ordered/unordered lists
  (including wrapped continuation lines), blockquote callouts, and inline
  code / bold / italic / links are all rendered.
- The output has a sticky sidebar with scroll-spy navigation, a hero with
  stat tiles, section "kickers", callouts and styled tables.

The stylesheet is embedded in the script, so the generated HTML has no
external assets other than Google Fonts, and the script needs no companion
files.

## Notes

- The version shown in the sidebar pill and hero is set by the `v1.NN` /
  `1.NN` literals in the page template inside the script; bump them on each
  release.
- The generator expects the README's structure (the section headings and
  Markdown constructs listed above). If you add unusual Markdown, check the
  generated HTML.
- Output is 7-bit ASCII; any typography is emitted as HTML entities.
