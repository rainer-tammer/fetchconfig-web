#!/usr/bin/env python3
# render-doc.py -- render fetchconfig-web-documentation.html from README.md
#
# Generates a single, self-contained HTML manual (embedded CSS, no external
# assets except Google Fonts) from the project README, in the same visual
# style as the upstream fetchconfig-documentation.html.
#
#   Usage:  python3 render-doc.py [README.md] [fetchconfig-web-documentation.html]
#
# Both arguments are optional; they default to README.md in the current
# directory and fetchconfig-web-documentation.html as the output. The script
# needs only the standard library (Python 3).
#
# It parses the README's Markdown (## sections, ###/#### headings, GitHub
# pipe tables, fenced code blocks, ordered/unordered lists with wrapped
# continuation lines, blockquote callouts, inline code/bold/italic/links) and
# emits a sticky-sidebar layout with scroll-spy navigation, a hero with stat
# tiles, numbered section kickers, callouts and styled tables. The version
# shown in the sidebar pill / hero and the minimum fetchconfig version in the
# hero warning are read from the APP_VERSION / MIN_FETCHCONFIG_VERSION
# constants in fetchconfig-web.cgi (same directory as this script), so they
# cannot drift from the code.
#
# fetchconfig-web - Web interface for the fetchconfig network configuration tool
# Copyright (C) 2026  Rainer Tammer
# Licensed under the GNU GPL v3 or later (see the LICENSE file).

import sys, re, io, os

# --- Python 2.7 / 3 compatibility -----------------------------------------
# html.escape (Py3) vs cgi.escape (Py2); io.open gives an encoding= kwarg on
# both. escape() quotes &, <, >, and (with quote=True) " and '.
try:
    from html import escape as _html_escape          # Python 3
except ImportError:                                   # Python 2.7
    from cgi import escape as _cgi_escape
    def _html_escape(s, quote=True):
        s = _cgi_escape(s, quote)
        if quote:
            s = s.replace("'", "&#x27;")              # cgi.escape leaves ' alone
        return s

class _HtmlShim(object):
    escape = staticmethod(_html_escape)
html = _HtmlShim()

def _open_utf8(path, mode='r'):
    return io.open(path, mode, encoding='utf-8')

# io.open(..., 'w', encoding=...) accepts only unicode on Python 2, so make
# sure whatever we write is unicode (a no-op on Python 3, where str is text).
try:
    _text_type = unicode          # Python 2
except NameError:
    _text_type = str              # Python 3
def to_text(s):
    if isinstance(s, bytes) and not isinstance(s, _text_type):
        return s.decode('utf-8')
    return s if isinstance(s, _text_type) else _text_type(s)

# --- I/O filenames (argv-overridable) --------------------------------------
# Correct invocation:  python render-doc.py [input.md] [output.html]
# A common mistake is to omit the script name, e.g. `python INSTALL.md out.html`,
# which makes Python try to EXECUTE the Markdown and fail with a confusing
# SyntaxError. Guard against it: if this file is not the program being run (so
# our own usage/help never fires), or the "input" is an .html while the
# "output" is a .md, explain the correct command and exit cleanly.
def _usage(msg):
    sys.stderr.write(
        "render-doc.py: %s\n"
        "Usage:  python render-doc.py [input.md] [output.html]\n"
        "  e.g.  python render-doc.py README.md  fetchconfig-web-documentation.html\n"
        "        python render-doc.py INSTALL.md fetchconfig-web-install.html\n"
        "Note: the SCRIPT name (render-doc.py) comes first, then the Markdown\n"
        "input, then the HTML output. Do not run 'python INSTALL.md ...'.\n"
        % msg)
    sys.exit(2)

README_IN = sys.argv[1] if len(sys.argv) > 1 else 'README.md'
HTML_OUT  = sys.argv[2] if len(sys.argv) > 2 else 'fetchconfig-web-documentation.html'

if README_IN.lower().endswith('.html') and HTML_OUT.lower().endswith(('.md', '.markdown')):
    _usage("arguments look reversed (input should be Markdown, output HTML)")
if not os.path.exists(README_IN):
    _usage("input file not found: %s" % README_IN)

# --- Embedded stylesheet + <style> wrapper (upstream doc's design system) --
STYLE = r"""<style>
  :root{
    --bg:#fbfbf9;
    --surface:#f1f4f4;
    --surface-2:#e9edee;
    --border:#dde3e3;
    --text:#141a1f;
    --text-muted:#5b6770;
    --text-faint:#8a949b;
    --accent:#0e7c8c;
    --accent-bright:#22aabb;
    --accent-soft:#e3f3f5;
    --danger:#c4432b;
    --danger-soft:#fbeae6;
    --success:#1c8a5b;
    --success-soft:#e8f5ee;
    --changed:#2451c4;
    --changed-soft:#e8edfb;
    --code-bg:#10171c;
    --code-text:#dce8ec;
    --code-accent:#7fe0cc;
    --code-muted:#7f929b;
    --radius:6px;
    --font-sans:'IBM Plex Sans',-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
    --font-mono:'IBM Plex Mono',ui-monospace,SFMono-Regular,Consolas,monospace;
    --sidebar-w:280px;
  }

  *{box-sizing:border-box;}
  html{scroll-behavior:smooth;}
  body{
    margin:0;
    font-family:var(--font-sans);
    color:var(--text);
    background:var(--bg);
    font-size:16px;
    line-height:1.6;
    -webkit-font-smoothing:antialiased;
  }

  a{color:var(--accent);text-decoration:none;}
  a:hover{text-decoration:underline;}
  a:focus-visible,button:focus-visible,input:focus-visible,summary:focus-visible{
    outline:2px solid var(--accent-bright);
    outline-offset:2px;
  }

  code, kbd{
    font-family:var(--font-mono);
    font-size:0.88em;
    background:var(--surface-2);
    border:1px solid var(--border);
    border-radius:4px;
    padding:0.1em 0.4em;
    color:var(--text);
    white-space:nowrap;
  }

  pre{
    font-family:var(--font-mono);
    background:var(--code-bg);
    color:var(--code-text);
    border-radius:var(--radius);
    padding:16px 18px;
    overflow-x:auto;
    font-size:0.86rem;
    line-height:1.65;
    margin:16px 0;
    border:1px solid #05090c;
  }
  pre code{
    background:none;
    border:none;
    padding:0;
    white-space:pre;
    color:inherit;
    font-size:1em;
  }
  pre .c{color:var(--code-muted);} /* comment */
  pre .s{color:var(--code-accent);} /* string / value */
  pre .k{color:#e8b95f;} /* keyword / flag */

  h1,h2,h3,h4{
    font-family:var(--font-sans);
    font-weight:600;
    line-height:1.25;
    color:var(--text);
    letter-spacing:-0.01em;
  }

  /* ---------- Layout ---------- */
  .layout{
    display:flex;
    align-items:flex-start;
    max-width:1600px;
    margin:0 auto;
  }

  .sidebar{
    position:sticky;
    top:0;
    height:100vh;
    width:var(--sidebar-w);
    flex:0 0 var(--sidebar-w);
    overflow-y:auto;
    padding:28px 22px 40px;
    border-right:1px solid var(--border);
    background:var(--surface);
  }

  .brand{
    display:flex;
    align-items:center;
    gap:10px;
    margin-bottom:4px;
  }
  .brand-mark{
    width:30px;height:30px;border-radius:7px;
    background:linear-gradient(155deg,var(--accent-bright),var(--accent));
    display:flex;align-items:center;justify-content:center;
    flex:0 0 auto;
  }
  .brand-mark svg{width:17px;height:17px;}
  .brand-name{font-weight:700;font-size:1.05rem;letter-spacing:-0.01em;}

  .brand-meta{
    font-family:var(--font-mono);
    font-size:0.72rem;
    color:var(--text-muted);
    margin:6px 0 22px;
    display:flex;
    gap:8px;
    flex-wrap:wrap;
  }
  .pill{
    display:inline-block;
    padding:2px 8px;
    border-radius:99px;
    background:var(--surface-2);
    border:1px solid var(--border);
    color:var(--text-muted);
  }

  .nav-group{margin-bottom:4px;}
  .nav-group-label{
    font-size:0.68rem;
    text-transform:uppercase;
    letter-spacing:0.08em;
    color:var(--text-faint);
    margin:20px 0 6px;
    font-weight:600;
  }
  .nav-group:first-of-type .nav-group-label{margin-top:0;}

  .sidebar nav a{
    display:block;
    color:var(--text-muted);
    font-size:0.885rem;
    padding:6px 10px;
    border-radius:5px;
    text-decoration:none;
    border-left:2px solid transparent;
    transition:background 0.12s ease, color 0.12s ease;
  }
  .sidebar nav a:hover{background:var(--surface-2);color:var(--text);}
  .sidebar nav a.active{
    color:var(--accent);
    background:var(--accent-soft);
    border-left-color:var(--accent-bright);
    font-weight:500;
  }

  .main-col{
    flex:1 1 auto;
    min-width:0;
    padding:0 0 120px;
  }

  .content{
    max-width:1200px;
    margin:0 auto;
    padding:0 48px;
  }
  /* Keep flowing prose at a comfortable reading measure, but let wide
     elements (tables, code blocks, diagrams) use the full content width so
     they don't need a horizontal scrollbar on a wide screen. */
  .content > p,
  .content > ul,
  .content > ol,
  .content > h2,
  .content > h3,
  .content > h4,
  .content > blockquote{
    max-width:820px;
  }
  .content > .table-wrap,
  .content > pre,
  .content > .callout{
    max-width:100%;
  }

  /* ---------- Hero ---------- */
  .hero{
    padding:64px 48px 48px;
    max-width:1200px;
    margin:0 auto;
    border-bottom:1px solid var(--border);
  }
  .hero-eyebrow{
    font-family:var(--font-mono);
    font-size:0.78rem;
    color:var(--accent);
    margin-bottom:14px;
  }
  .hero h1{
    font-size:2.6rem;
    margin:0 0 14px;
    letter-spacing:-0.02em;
  }
  .hero p.lede{
    font-size:1.13rem;
    color:var(--text-muted);
    max-width:640px;
    margin:0 0 28px;
    line-height:1.6;
  }
  .hero-stats{
    display:flex;
    gap:36px;
    flex-wrap:wrap;
    margin-top:8px;
  }
  .hero-stat .num{
    font-family:var(--font-mono);
    font-size:1.6rem;
    font-weight:600;
    color:var(--text);
    display:block;
  }
  .hero-stat .label{
    font-size:0.8rem;
    color:var(--text-muted);
  }

  /* ---------- Sections ---------- */
  section{
    padding:56px 0 8px;
    border-bottom:1px solid var(--border);
  }
  section:last-of-type{border-bottom:none;}

  .section-kicker{
    font-family:var(--font-mono);
    font-size:0.75rem;
    color:var(--text-faint);
    margin-bottom:8px;
  }
  h2{
    font-size:1.65rem;
    margin:0 0 18px;
    scroll-margin-top:24px;
  }
  h3{
    font-size:1.18rem;
    margin:34px 0 12px;
    scroll-margin-top:24px;
  }
  h4{
    font-size:0.98rem;
    margin:22px 0 8px;
    color:var(--text);
    scroll-margin-top:24px;
  }
  p{margin:0 0 14px;color:var(--text);}
  section p, section li{color:var(--text);}
  ul,ol{padding-left:1.3em;margin:0 0 16px;}
  li{margin-bottom:6px;}
  .prose-muted{color:var(--text-muted);}

  .file-label{
    font-family:var(--font-mono);
    font-size:0.72rem;
    color:var(--text-faint);
    margin:18px 0 -8px;
    display:block;
  }

  /* ---------- Callouts ---------- */
  .callout{
    border-radius:var(--radius);
    padding:16px 18px;
    margin:18px 0;
    border:1px solid var(--border);
    background:var(--surface);
    font-size:0.93rem;
  }
  .callout-title{
    font-weight:600;
    font-size:0.82rem;
    text-transform:uppercase;
    letter-spacing:0.05em;
    margin-bottom:6px;
    display:flex;
    align-items:center;
    gap:7px;
  }
  .callout.warn{background:var(--danger-soft);border-color:#f0c9bd;}
  .callout.warn .callout-title{color:var(--danger);}
  .callout.note{background:var(--accent-soft);border-color:#bfe4e9;}
  .callout.note .callout-title{color:var(--accent);}
  .callout p:last-child{margin-bottom:0;}

  /* ---------- Tables ---------- */
  .table-wrap{overflow-x:auto;margin:18px 0 26px;border:1px solid var(--border);border-radius:var(--radius);}
  table{
    border-collapse:collapse;
    width:100%;
    font-size:0.87rem;
  }
  caption{
    text-align:left;
    font-size:0.78rem;
    color:var(--text-muted);
    padding:8px 14px;
    background:var(--surface);
    border-bottom:1px solid var(--border);
    caption-side:top;
  }
  th,td{
    text-align:left;
    padding:9px 14px;
    border-bottom:1px solid var(--border);
    vertical-align:top;
  }
  thead th{
    background:var(--surface);
    font-weight:600;
    font-size:0.76rem;
    text-transform:uppercase;
    letter-spacing:0.04em;
    color:var(--text-muted);
    white-space:nowrap;
  }
  tbody tr:last-child td{border-bottom:none;}
  tbody tr:hover{background:var(--surface);}
  td code, th code{white-space:nowrap;}
  .req-yes{color:var(--danger);font-weight:600;font-size:0.82rem;}
  .req-opt{color:var(--text-faint);font-size:0.82rem;}
  .req-dash{color:var(--border);}
  .matrix th, .matrix td{text-align:center;}
  .matrix td:first-child, .matrix th:first-child{text-align:left;}
  .matrix{font-size:0.8rem;}
  .matrix code{white-space:nowrap;}

  /* ---------- Flag reference ---------- */
  .flag-card{
    border:1px solid var(--border);
    border-radius:var(--radius);
    padding:16px 18px;
    margin:14px 0;
    background:var(--bg);
  }
  .flag-card + .flag-card{margin-top:10px;}
  .flag-head{
    display:flex;
    align-items:baseline;
    gap:10px;
    flex-wrap:wrap;
    margin-bottom:8px;
  }
  .flag-tag{
    font-family:var(--font-mono);
    font-weight:600;
    background:var(--code-bg);
    color:var(--code-accent);
    border-radius:4px;
    padding:3px 9px;
    font-size:0.86rem;
  }
  .flag-req{
    font-size:0.72rem;
    font-family:var(--font-mono);
    color:var(--text-faint);
  }
  .flag-card p{margin-bottom:8px;font-size:0.92rem;color:var(--text-muted);}
  .flag-card p:last-child{margin-bottom:0;}
  .exit-list{list-style:none;padding:0;margin:8px 0 0;font-family:var(--font-mono);font-size:0.82rem;}
  .exit-list li{display:flex;gap:10px;margin-bottom:3px;}
  .exit-list .code{color:var(--text);font-weight:600;min-width:1.6em;}

  /* ---------- Color swatches (email notif) ---------- */
  .swatches{display:flex;gap:14px;flex-wrap:wrap;margin:18px 0 22px;}
  .swatch{
    display:flex;align-items:center;gap:9px;
    border:1px solid var(--border);border-radius:99px;
    padding:5px 12px 5px 6px;font-size:0.82rem;background:var(--surface);
  }
  .swatch .dot{width:16px;height:16px;border-radius:50%;flex:0 0 auto;border:1px solid rgba(0,0,0,0.12);}

  /* ---------- Toggle tabs (Installation) ---------- */
  .tabs{margin:18px 0;}
  input.tab-input{position:absolute;opacity:0;pointer-events:none;}
  .tab-labels{display:flex;gap:4px;border-bottom:1px solid var(--border);margin-bottom:20px;}
  .tab-labels label{
    font-size:0.88rem;font-weight:500;color:var(--text-muted);
    padding:9px 16px;cursor:pointer;border-bottom:2px solid transparent;
    margin-bottom:-1px;
  }
  .tab-panel{display:none;}
  #tab-unix:checked ~ .tab-labels label[for="tab-unix"],
  #tab-win:checked ~ .tab-labels label[for="tab-win"]{
    color:var(--accent);border-bottom-color:var(--accent-bright);
  }
  #tab-unix:checked ~ .tab-panels #panel-unix,
  #tab-win:checked ~ .tab-panels #panel-win{display:block;}

  /* ---------- Device support grid ---------- */
  .device-grid td:first-child code{font-weight:600;}

  /* ---------- Footer ---------- */
  .page-footer{
    max-width:1200px;margin:0 auto;padding:40px 48px 60px;
    color:var(--text-faint);font-size:0.82rem;
  }
  .page-footer a{color:var(--text-muted);}

  /* ---------- Mobile nav ---------- */
  .nav-toggle{display:none;}
  .mobile-bar{display:none;}

  @media (max-width: 900px){
    .sidebar{
      position:fixed;
      inset:0 auto 0 0;
      z-index:40;
      transform:translateX(-100%);
      transition:transform 0.2s ease;
      box-shadow:2px 0 24px rgba(0,0,0,0.15);
    }
    .nav-toggle:checked ~ .layout .sidebar{transform:translateX(0);}
    .mobile-bar{
      display:flex;align-items:center;justify-content:space-between;
      position:sticky;top:0;z-index:30;
      background:var(--bg);border-bottom:1px solid var(--border);
      padding:14px 20px;
    }
    .mobile-bar .brand{margin:0;}
    .mobile-bar label{
      font-family:var(--font-mono);font-size:0.8rem;
      border:1px solid var(--border);border-radius:6px;padding:6px 10px;cursor:pointer;
    }
    .content{padding:0 22px;}
    .hero{padding:36px 22px 32px;}
    .hero h1{font-size:2rem;}
    .page-footer{padding:32px 22px 48px;}
  }
  @media (min-width:901px){
    .mobile-bar{display:none !important;}
  }

  @media print{
    .sidebar,.mobile-bar{display:none !important;}
    .layout{display:block;}
    a{color:inherit;text-decoration:none;}
    pre{white-space:pre-wrap;}
  }
</style>
"""


readme = _open_utf8(README_IN).read()
style  = STYLE

# --- verbatim license mode -------------------------------------------------
# The GPLv3 LICENSE is a fixed legal document: it must be reproduced EXACTLY,
# not reflowed or reformatted as Markdown prose. When the input is a LICENSE
# file (basename "LICENSE", or any file with no .md/.markdown/.html suffix),
# render it verbatim inside a <pre> block, and also emit a LICENSE.md that wraps
# the same text in a fenced code block. This keeps the legal text byte-exact.
def _looks_like_license(path):
    base = os.path.basename(path)
    if base.upper().startswith('LICENSE') and '.' not in base:
        return True
    low = path.lower()
    return not low.endswith(('.md', '.markdown', '.html', '.htm'))

if _looks_like_license(README_IN):
    _title = 'GNU General Public License, Version 3'
    # LICENSE.md: verbatim text in a fenced block (so Markdown viewers show it
    # unaltered). Derive the .md path from the HTML output path.
    _md_out = re.sub(r'\.html?$', '', HTML_OUT, flags=re.I) + '.md'
    if _md_out == HTML_OUT:
        _md_out = HTML_OUT + '.md'
    with _open_utf8(_md_out, 'w') as _f:
        _f.write('# ' + _title + '\n\n```\n' + readme.rstrip('\n') + '\n```\n')
    # LICENSE.html: the text inside a <pre> in the standard page shell.
    _pre = _html_escape(readme.rstrip('\n'))
    _lic_page = (u"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>fetchconfig-web &mdash; {title}</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:ital,wght@0,400;0,500;0,600;0,700;1,400&family=IBM+Plex+Mono:wght@400;500;600&display=swap" rel="stylesheet">
{style}
<style>
  .license-wrap{{max-width:900px;margin:0 auto;padding:40px 22px 64px;}}
  .license-wrap .hero-eyebrow{{text-transform:uppercase;letter-spacing:.08em;font-size:.8rem;color:var(--accent);font-weight:600;}}
  .license-wrap h1{{font-size:2rem;margin:.2em 0 1rem;}}
  pre.license-text{{white-space:pre-wrap;word-wrap:break-word;overflow-wrap:anywhere;
    font-family:'IBM Plex Mono',ui-monospace,Menlo,Consolas,monospace;font-size:.82rem;
    line-height:1.5;background:var(--card,#fff);border:1px solid var(--border,#e2e5ea);
    border-radius:8px;padding:1.2em 1.4em;color:var(--ink,#1a2129);}}
</style>
</head>
<body>
<div class="license-wrap">
  <div class="hero-eyebrow">License</div>
  <h1>{title}</h1>
  <pre class="license-text">{body}</pre>
</div>
</body>
</html>
""").format(title=html.escape(_title), style=style, body=_pre)
    with _open_utf8(HTML_OUT, 'w') as _f:
        _f.write(_lic_page)
    sys.stderr.write("wrote %s and %s (verbatim GPLv3)\n" % (HTML_OUT, _md_out))
    sys.exit(0)

# ---- split README into top-level (##) sections; keep the H1 intro separately
lines = readme.split('\n')
# find first '## '
sections = []   # (title, body_lines)
intro = []
cur_title = None
cur_body = []
started = False
for ln in lines:
    m = re.match(r'^## (.+)$', ln)
    if m:
        if cur_title is None:
            intro = cur_body[:]        # everything before first ## (incl H1)
        else:
            sections.append((cur_title, cur_body))
        cur_title = m.group(1).strip()
        cur_body = []
        started = True
    else:
        cur_body.append(ln)
if cur_title is not None:
    sections.append((cur_title, cur_body))
else:
    intro = cur_body

def slug(t):
    s = re.sub(r'[^a-z0-9]+','-', t.lower()).strip('-')
    return s

# ---- inline markdown: code, bold, italic, links -> HTML (with escaping)
def inline(text):
    # protect inline code first
    parts = []
    idx = 0
    for m in re.finditer(r'`([^`]+)`', text):
        parts.append(('t', text[idx:m.start()]))
        parts.append(('c', m.group(1)))
        idx = m.end()
    parts.append(('t', text[idx:]))
    out = ''
    for kind, seg in parts:
        if kind == 'c':
            out += '<code>' + html.escape(seg) + '</code>'
        else:
            seg = html.escape(seg)
            # links [text](url)
            seg = re.sub(r'\[([^\]]+)\]\(([^)]+)\)', lambda m: '<a href="%s">%s</a>' % (html.escape(m.group(2)), m.group(1)), seg)
            out += seg
    # Protect any run of 3+ asterisks and the password-mask literal so the
    # bold/italic passes below don't chew them up (e.g. "?***?").
    out = out.replace('***', '\x00AST3\x00')
    # Bold/italic AFTER code protection so **`code`** works (the ** are outside
    # the <code> span). Non-greedy; do not let a match cross a "**" boundary.
    out = re.sub(r'\*\*([^*]+(?:\*(?!\*)[^*]+)*)\*\*', r'<strong>\1</strong>', out)
    out = re.sub(r'(?<!\*)\*(?!\*)([^*]+)\*(?!\*)', r'<em>\1</em>', out)
    out = out.replace('\x00AST3\x00', '***')
    return out

# ---- block renderer for a body (list of lines) -> HTML string
def render_body(body):
    out = []
    i = 0
    n = len(body)
    while i < n:
        ln = body[i]
        # fenced code block
        if re.match(r'^```', ln):
            lang = ln.strip('`').strip()
            code = []
            i += 1
            while i < n and not re.match(r'^```', body[i]):
                code.append(body[i]); i += 1
            i += 1  # skip closing ```
            label = {'':'code','sql':'sql','sh':'shell','bash':'shell','perl':'perl','text':'text'}.get(lang, lang or 'code')
            out.append('<span class="file-label">%s</span>' % html.escape(label))
            esc = html.escape('\n'.join(code))
            # simple comment highlight for # / -- / :: lines
            hl = []
            for cl in esc.split('\n'):
                if re.match(r'^\s*(#|--|::)', cl):
                    hl.append('<span class="c">%s</span>' % cl)
                else:
                    hl.append(cl)
            out.append('<pre><code>%s</code></pre>' % '\n'.join(hl))
            continue
        # table (GitHub pipe table): header line + --- line
        if '|' in ln and i+1 < n and re.match(r'^\s*\|?[\s:|-]+\|[\s:|-]+', body[i+1]) and '-' in body[i+1]:
            header = [c.strip() for c in ln.strip().strip('|').split('|')]
            i += 2
            rows = []
            while i < n and '|' in body[i] and body[i].strip():
                rows.append([c.strip() for c in body[i].strip().strip('|').split('|')])
                i += 1
            th = ''.join('<th>%s</th>' % inline(c) for c in header)
            trs = ''
            for r in rows:
                tds = ''.join('<td>%s</td>' % inline(c) for c in r)
                trs += '<tr>%s</tr>' % tds
            out.append('<div class="table-wrap"><table><thead><tr>%s</tr></thead><tbody>%s</tbody></table></div>' % (th, trs))
            continue
        # heading ### / #### -- give it an id (slug of its text) so the sidebar
        # nav links resolve to it.
        m = re.match(r'^(#{3,4}) (.+)$', ln)
        if m:
            lvl = len(m.group(1))
            htext = m.group(2).strip()
            out.append('<h%d id="%s">%s</h%d>' % (lvl, slug(htext), inline(htext), lvl))
            i += 1
            continue
        # blockquote -> callout note. Strip the "> " prefix and render the
        # inner content as blocks (so nested fenced code, lists and multiple
        # paragraphs inside a blockquote render correctly instead of being
        # flattened into one line).
        # A GitHub alert marker on the first line ("> [!CAUTION]" etc.) picks
        # the callout style: CAUTION/WARNING -> red "warn", anything else ->
        # "note". The marker line itself is not rendered.
        if re.match(r'^> ?', ln):
            inner = []
            while i < n and re.match(r'^> ?', body[i]):
                inner.append(re.sub(r'^> ?', '', body[i])); i += 1
            cls = 'note'
            am = re.match(r'^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*$', inner[0]) if inner else None
            if am:
                cls = 'warn' if am.group(1) in ('WARNING', 'CAUTION') else 'note'
                inner = inner[1:]
            out.append('<div class="callout %s">%s</div>' % (cls, render_body(inner)))
            continue
        # unordered list (absorb indented continuation lines into the item)
        if re.match(r'^\s*[-*] ', ln):
            items = []
            while i < n and re.match(r'^\s*[-*] ', body[i]):
                cur = re.sub(r'^\s*[-*] ','',body[i]); i += 1
                while i < n and re.match(r'^\s+\S', body[i]) and not re.match(r'^\s*[-*] |^\s*\d+\. ', body[i]):
                    cur += ' ' + body[i].strip(); i += 1
                items.append(cur)
            out.append('<ul>%s</ul>' % ''.join('<li>%s</li>' % inline(x) for x in items))
            continue
        # ordered list (absorb indented continuation lines into the item)
        if re.match(r'^\s*\d+\. ', ln):
            items = []
            while i < n and re.match(r'^\s*\d+\. ', body[i]):
                cur = re.sub(r'^\s*\d+\. ','',body[i]); i += 1
                while i < n and re.match(r'^\s+\S', body[i]) and not re.match(r'^\s*[-*] |^\s*\d+\. ', body[i]):
                    cur += ' ' + body[i].strip(); i += 1
                items.append(cur)
            out.append('<ol>%s</ol>' % ''.join('<li>%s</li>' % inline(x) for x in items))
            continue
        # blank
        if ln.strip() == '':
            i += 1
            continue
        # paragraph (gather until blank / block start)
        para = [ln]
        i += 1
        while i < n and body[i].strip() and not re.match(r'^(```|#{2,4} |\s*[-*] |\s*\d+\. |> )', body[i]) and not ('|' in body[i] and i+1<n and '-' in (body[i+1] if i+1<n else '')):
            para.append(body[i]); i += 1
        out.append('<p>%s</p>' % inline(' '.join(para)))
    return '\n'.join(out)

# ---- intro: strip the H1, keep the rest as the hero lede + first section
intro_text = '\n'.join(intro)

# ---- build sidebar nav directly from the actual document structure.
# Each top-level (##) section becomes a nav group; its ### subsections become
# the links under it. This stays in sync with the README automatically instead
# of a hardcoded title map. A "Part N -- Name" heading is shown as just "Name";
# a ## section with no ### subsections links to itself.
def nav_html():
    parts = []
    for title, body in sections:
        if title == 'Contents':
            continue   # the sidebar replaces the in-document Contents list
        group_label = re.sub(r'^Part\s+\d+\s*--\s*', '', title).strip()
        # collect ### subsections within this section
        subs = []
        for ln in body:
            m = re.match(r'^### (.+)$', ln)
            if m:
                st = m.group(1).strip()
                subs.append(st)
        if subs:
            links = ''.join(
                '<a href="#%s">%s</a>' % (slug(st), inline(st)) for st in subs
            )
            parts.append('<div class="nav-group"><div class="nav-group-label">%s</div>%s</div>'
                         % (html.escape(group_label), links))
        else:
            # standalone section (e.g. Security model, License): link to itself
            parts.append('<div class="nav-group">'
                         '<a href="#%s">%s</a></div>' % (slug(title), inline(title)))
    return '\n'.join(parts)

# ---- sections html with numbered kickers
sec_html = []
for idx,(title, body) in enumerate(sections, start=1):
    sec_html.append(
        '<section id="%s">\n<div class="section-kicker">%02d</div>\n<h2>%s</h2>\n%s\n</section>'
        % (slug(title), idx, inline(title), render_body(body))
    )

# Title, eyebrow and hero lede are derived from the INPUT document so the same
# renderer serves README.md ("fetchconfig-web ... Documentation") and
# INSTALL.md ("fetchconfig-web -- Installation") correctly:
#   - the H1 "fetchconfig-web -- <Subtitle>" gives the eyebrow (<Subtitle>);
#     a bare "fetchconfig-web" H1 falls back to "Documentation";
#   - the lede is the first non-empty intro paragraph after the H1.
_h1 = ''
_lede_lines = []
for _ln in intro:
    if not _h1 and _ln.startswith('# '):
        _h1 = _ln[2:].strip(); continue
    if _h1:
        if _ln.strip() == '':
            if _lede_lines: break
            continue
        if _ln.startswith('#'): break
        _lede_lines.append(_ln.strip())
_m = re.match(r'^fetchconfig-web\s*(?:--|-|\u2014)\s*(.+)$', _h1)
eyebrow = _m.group(1).strip() if _m else 'Documentation'
page_title = 'fetchconfig-web &mdash; ' + html.escape(eyebrow)
lede = inline(' '.join(_lede_lines)) if _lede_lines else \
    "A single-file Perl CGI front-end for fetchconfig: a browser UI for browsing device backups, viewing and comparing configurations, checking run status, and editing the device table &mdash; backed by a PostgreSQL user database."

# Version strings for the sidebar pill, hero tile and hero warning, read from
# fetchconfig-web.cgi next to this script. Falls back to '?' with a warning on
# stderr if the file or a constant is missing.
def cgi_constant(name):
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'fetchconfig-web.cgi')
    try:
        with io.open(path, encoding='utf-8', errors='replace') as f:
            txt = f.read()
    except (IOError, OSError) as e:
        sys.stderr.write("render-doc.py: cannot read %s: %s\n" % (path, e))
        return '?'
    m = re.search(r"^use constant %s\s*=>\s*'([^']+)'" % re.escape(name), txt, re.M)
    if not m:
        sys.stderr.write("render-doc.py: constant %s not found in %s\n" % (name, path))
        return '?'
    return m.group(1)

app_version = html.escape(cgi_constant('APP_VERSION_INTERNAL'))
min_fc_version = html.escape(cgi_constant('MIN_FETCHCONFIG_VERSION'))

# Precompute the dynamic pieces so the template below uses only simple named
# placeholders -- str.format() (used for Python 2.7 compatibility) cannot call
# functions or run expressions inside the template.
nav = nav_html()
sections = chr(10).join(sec_html)

page = (u"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{page_title}</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:ital,wght@0,400;0,500;0,600;0,700;1,400&family=IBM+Plex+Mono:wght@400;500;600&display=swap" rel="stylesheet">
{style}
</head>
<body>

<input type="checkbox" id="nav-toggle" class="nav-toggle">

<div class="mobile-bar">
  <div class="brand">
    <span class="brand-mark"><svg viewBox="0 0 24 24" fill="none"><path d="M4 12h16M4 6h10M4 18h7" stroke="white" stroke-width="2" stroke-linecap="round"/></svg></span>
    <span class="brand-name">fetchconfig-web</span>
  </div>
  <label for="nav-toggle">Menu</label>
</div>

<div class="layout">

  <aside class="sidebar">
    <div class="brand">
      <span class="brand-mark"><svg viewBox="0 0 24 24" fill="none"><path d="M4 12h16M4 6h10M4 18h7" stroke="white" stroke-width="2" stroke-linecap="round"/></svg></span>
      <span class="brand-name">fetchconfig-web</span>
    </div>
    <div class="brand-meta">
      <span class="pill">v{app_version}</span>
      <span class="pill">GPL&#8209;3.0+</span>
    </div>

    <nav>
{nav}
    </nav>
  </aside>

  <div class="main-col">

    <div class="hero">
      <div class="hero-eyebrow">{eyebrow}</div>
      <h1>fetchconfig-web</h1>
      <p class="lede">{lede}</p>
      <div class="callout warn" style="margin-top:1rem">
        <p><strong>Requires fetchconfig {min_fc_version} or newer.</strong> The installed
        version is read from <code>&lt;FETCHCONFIG_PATH&gt;/fetchconfig/Constants.pm</code>;
        a warning banner is shown on every page (after login) if it is older
        than {min_fc_version} or cannot be determined.</p>
      </div>
      <div class="callout warn" style="margin-top:1rem">
        <p><strong>Long backups and web server timeouts.</strong> While Backup
        Now or the Empty Backup Cleanup scan runs, a keepalive is sent every
        10 s, so the web server's inactivity timeout (Apache <code>Timeout</code>)
        only needs to be longer than 10 s and <code>BACKUP_TIMEOUT</code> may exceed
        it. <code>BACKUP_TIMEOUT</code> must be higher than the longest backup
        run of any device in the device table. A reverse proxy or load balancer
        in front must not buffer the response.</p>
      </div>
      <div class="hero-stats">
        <div class="hero-stat"><span class="num">{app_version}</span><span class="label">version</span></div>
        <div class="hero-stat"><span class="num">Perl CGI</span><span class="label">single file</span></div>
        <div class="hero-stat"><span class="num">PostgreSQL</span><span class="label">user database</span></div>
        <div class="hero-stat"><span class="num">Devices / Status / Tools</span><span class="label">web pages</span></div>
      </div>
    </div>

    <div class="content">

{sections}

    </div>

    <div class="page-footer">
      Generated from the fetchconfig-web README &middot; Rainer Tammer &middot; GPL&#8209;3.0-or-later
    </div>

  </div>
</div>

<script>
  // Scroll-spy: highlight the sidebar link matching the section in view.
  (function(){{
    var links = Array.prototype.slice.call(document.querySelectorAll('.sidebar nav a'));
    var sections = links.map(function(a){{ return document.querySelector(a.getAttribute('href')); }}).filter(Boolean);
    if (!('IntersectionObserver' in window) || !sections.length) return;
    var current = null;
    function setActive(id){{
      if (id === current) return;
      current = id;
      links.forEach(function(a){{ a.classList.toggle('active', a.getAttribute('href') === '#' + id); }});
    }}
    var observer = new IntersectionObserver(function(entries){{
      var visible = entries.filter(function(e){{ return e.isIntersecting; }});
      if (visible.length){{
        visible.sort(function(a,b){{ return a.boundingClientRect.top - b.boundingClientRect.top; }});
        setActive(visible[0].target.id);
      }}
    }}, {{ rootMargin: '-10% 0px -70% 0px', threshold: 0 }});
    sections.forEach(function(s){{ observer.observe(s); }});
    setActive(sections[0].id);
    var toggle = document.getElementById('nav-toggle');
    links.forEach(function(a){{ a.addEventListener('click', function(){{ if (toggle) toggle.checked = false; }}); }});
  }})();
</script>

</body>
</html>
""").format(style=style, lede=lede, nav=nav, sections=sections,
            page_title=page_title, eyebrow=html.escape(eyebrow),
            app_version=app_version, min_fc_version=min_fc_version)
_open_utf8(HTML_OUT, 'w').write(to_text(page))
print("wrote %s: %d bytes, %d sections" % (HTML_OUT, len(page), len(sec_html)))
