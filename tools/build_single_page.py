"""Build one self-contained HTML file of the student website, to upload to any web server.

    python tools/build_single_page.py            -> upload/cloudearthi-mooc.html

The stylesheet, the script and the logo are put inside the file. Links to the certificate and profile pages point to
the GitHub Pages copies, which stay the verification address for awards.
"""
import base64
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
PAGES = "https://octainsight.github.io/mooc/"
OUT = ROOT / "upload" / "cloudearthi-mooc.html"


def data_uri(path: pathlib.Path) -> str:
    return "data:image/png;base64," + base64.b64encode(path.read_bytes()).decode("ascii")


def main():
    html = (DOCS / "index.html").read_text(encoding="utf-8")
    css = (DOCS / "assets" / "site.css").read_text(encoding="utf-8")
    js = (DOCS / "assets" / "site.js").read_text(encoding="utf-8")
    logo, icon = data_uri(DOCS / "assets" / "logo.png"), data_uri(DOCS / "assets" / "favicon.png")

    js = js.replace('"award.html?id=', f'"{PAGES}award.html?id=').replace('`award.html?id=', f'`{PAGES}award.html?id=')
    js = js.replace('href="award.html?id=', f'href="{PAGES}award.html?id=').replace('href="profile.html?u=', f'href="{PAGES}profile.html?u=')
    if re.search(r'(?<![/\w])(award|profile)\.html', js):
        raise SystemExit("a relative award/profile link is left in site.js")
    js = js.replace("</script", "<\\/script")

    html = html.replace('<link rel="stylesheet" href="assets/site.css">', f"<style>\n{css}\n</style>")
    html = html.replace('<script src="assets/site.js"></script>', f"<script>\n{js}\n</script>")
    html = html.replace('src="assets/logo.png"', f'src="{logo}"')
    html = html.replace('href="assets/favicon.png"', f'href="{icon}"').replace('href="assets/apple-touch-icon.png"', f'href="{icon}"')
    if "assets/" in html:
        raise SystemExit("a link to assets/ is left in the page")
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(html, encoding="utf-8")
    print(f"{OUT.relative_to(ROOT)}: {OUT.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
