"""Copy the shared site header and footer into the student pages.

    python tools/sync_footer.py

docs/assets/sitehead.html and sitefoot.html hold the header (the same menu as the WordPress site) and the footer;
their styles are in sitehead.css and sitefoot.css. GitHub Pages serves the pages as they are, so header and footer
are copied into each page between markers. In the header, {{MOOC}} becomes "" on the MOOC page itself (links stay
on the page) and the full address of mooc.html on the award and profile pages.
Run this after changing either file, then run tools/build_single_page.py.
"""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
MOOC = "https://mooc.cloudearthi.com/mooc.html"
PAGES = {"index.html": "", "award.html": MOOC, "profile.html": MOOC}
FONTS = ('<link href="https://fonts.googleapis.com/css2?family=Atkinson+Hyperlegible:ital,wght@0,400;0,700;1,400'
         '&family=Bricolage+Grotesque:opsz,wght@12..96,500..800&display=swap" rel="stylesheet">')


def block(html, start, end, content, where):
    piece = f"{start}\n{content.strip()}\n{end}"
    if start in html:
        return html[:html.index(start)] + piece + html[html.index(end) + len(end):]
    return where(html, piece)


def ensure_link(html, href):
    tag = f'<link rel="stylesheet" href="{href}">'
    return html if tag in html else html.replace("</head>", f"{tag}\n</head>", 1)


def sync(page: pathlib.Path, mooc: str, head: str, foot: str) -> bool:
    html = page.read_text(encoding="utf-8")
    old = html
    html = block(html, "<!-- site header: start -->", "<!-- site header: end -->", head.replace("{{MOOC}}", mooc),
                 lambda h, p: re.sub(r"<body([^>]*)>", lambda m: f"<body{m.group(1)}>\n{p}", h, count=1))
    html = block(html, "<!-- site footer: start -->", "<!-- site footer: end -->", foot,
                 lambda h, p: h.replace("</body>", f"{p}\n</body>", 1))
    html = ensure_link(ensure_link(html, "assets/sitehead.css"), "assets/sitefoot.css")
    if "Bricolage+Grotesque" not in html:
        html = html.replace("</head>", f"{FONTS}\n</head>", 1)
    page.write_text(html, encoding="utf-8")
    return html != old


def main():
    head = (DOCS / "assets" / "sitehead.html").read_text(encoding="utf-8")
    foot = (DOCS / "assets" / "sitefoot.html").read_text(encoding="utf-8")
    for name, mooc in PAGES.items():
        print(name, "updated" if sync(DOCS / name, mooc, head, foot) else "unchanged")


if __name__ == "__main__":
    main()
