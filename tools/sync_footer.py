"""Copy the shared site footer into the student pages.

    python tools/sync_footer.py

docs/assets/sitefoot.html holds the footer (the same as the WordPress site's footer); its styles are in
docs/assets/sitefoot.css. GitHub Pages serves the pages as they are, so the footer is copied into each page between
the markers below. Run this after changing sitefoot.html, then run tools/build_single_page.py.
"""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
START, END = "<!-- site footer: start -->", "<!-- site footer: end -->"
PAGES = ("index.html", "award.html", "profile.html")


def sync(page: pathlib.Path, footer: str) -> bool:
    html = page.read_text(encoding="utf-8")
    block = f"{START}\n{footer.strip()}\n{END}"
    if START in html:
        new = html[:html.index(START)] + block + html[html.index(END) + len(END):]
    else:
        new = html.replace("</body>", f"{block}\n</body>", 1)
    if '<link rel="stylesheet" href="assets/sitefoot.css">' not in new:
        new = new.replace("</head>", '<link rel="stylesheet" href="assets/sitefoot.css">\n</head>', 1)
    page.write_text(new, encoding="utf-8")
    return new != html


def main():
    footer = (DOCS / "assets" / "sitefoot.html").read_text(encoding="utf-8")
    for name in PAGES:
        print(name, "updated" if sync(DOCS / name, footer) else "unchanged")


if __name__ == "__main__":
    main()
