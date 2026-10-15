#!/usr/bin/env python3
# render-changes.py -- generate plain-text CHANGES and CHANGES.html from the
# Markdown master CHANGES.md.
#
#   python3 render-changes.py            # CHANGES.md -> CHANGES + CHANGES.html
#   python3 render-changes.py in.md      # in.md -> CHANGES + CHANGES.html
#
# CHANGES (plain text): drop the document H1, turn "## X" into "X" + "====",
# "### X" into "X" + "----", strip inline-code backticks, keep list bullets.
# CHANGES.html: a small self-contained changelog page (not the README template).
import sys, io, re, html

SRC  = sys.argv[1] if len(sys.argv) > 1 else 'CHANGES.md'
TXT  = 'CHANGES'
HTML = 'CHANGES.html'
md = io.open(SRC, encoding='utf-8').read()

# ---------- plain-text ----------
def to_text(md):
    out = []
    for line in md.split('\n'):
        if re.match(r'^#\s+', line):                 # doc H1 -> drop
            continue
        m = re.match(r'^##\s+(.*)$', line)           # version -> Setext H1
        if m:
            t = m.group(1).rstrip(); out += [t, '=' * len(t)]; continue
        m = re.match(r'^###\s+(.*)$', line)          # section -> Setext H2
        if m:
            t = m.group(1).rstrip(); out += [t, '-' * len(t)]; continue
        out.append(re.sub(r'`([^`]*)`', r'\1', line))
    txt = re.sub(r'\n{3,}', '\n\n', '\n'.join(out)).lstrip('\n')
    return txt.rstrip('\n') + '\n'

io.open(TXT, 'w', encoding='utf-8').write(to_text(md))
print("wrote %s" % TXT)

# ---------- HTML ----------
def inline(s):
    s = html.escape(s)
    s = re.sub(r'`([^`]*)`', r'<code>\1</code>', s)
    return s

body, in_ul = [], False
title = 'Change log'
for line in md.split('\n'):
    m = re.match(r'^#\s+(.*)$', line)
    if m: title = m.group(1); continue
    m = re.match(r'^##\s+(.*)$', line)
    if m:
        if in_ul: body.append('</ul>'); in_ul = False
        v = m.group(1).strip()
        aid = re.sub(r'[^\w.]+', '-', v)
        body.append(f'<h2 id="{aid}">{inline(v)}</h2>'); continue
    m = re.match(r'^###\s+(.*)$', line)
    if m:
        if in_ul: body.append('</ul>'); in_ul = False
        body.append(f'<h3>{inline(m.group(1).strip())}</h3>'); continue
    m = re.match(r'^\* (.*)$', line)                  # bullet (may continue)
    if m:
        if not in_ul: body.append('<ul>'); in_ul = True
        body.append(f'<li>{inline(m.group(1))}')      # closed on next bullet/blank
        continue
    if re.match(r'^  \S', line) and in_ul:            # bullet continuation
        body[-1] += ' ' + inline(line.strip()); continue
    # blank or paragraph
    if in_ul:
        body.append('</ul>'); in_ul = False
    if line.strip():
        body.append(f'<p>{inline(line.strip())}</p>')
if in_ul: body.append('</ul>')

doc = """<!DOCTYPE html>
<html lang="en"><head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>%s</title>
<style>
  body { font-family: -apple-system, "Segoe UI", Helvetica, Arial, sans-serif;
         color: #222; background: #f4f5f7; margin: 0; line-height: 1.5; }
  main { max-width: 820px; margin: 0 auto; padding: 2em 1.2em 4em; }
  h1 { font-size: 1.6em; margin: 0 0 1em; }
  h2 { margin: 1.6em 0 0.2em; padding: 0.3em 0.6em; background: #b7e6cd;
       border-radius: 6px; font-size: 1.25em; }
  h3 { margin: 1.1em 0 0.3em; color: #1f4e79; font-size: 1.05em;
       border-bottom: 1px solid #cdeede; padding-bottom: 0.15em; }
  ul { margin: 0.4em 0 0.8em; padding-left: 1.3em; }
  li { margin: 0.35em 0; }
  p  { margin: 0.5em 0; }
  code { font-family: Consolas, Menlo, "Courier New", monospace;
         background: #eef1f4; padding: 0 0.3em; border-radius: 3px;
         font-size: 0.92em; }
</style></head><body><main>
<h1>%s</h1>
%s
</main></body></html>
""" % (html.escape(title), inline(title), '\n'.join(body))
io.open(HTML, 'w', encoding='utf-8').write(doc)
print("wrote %s" % HTML)
