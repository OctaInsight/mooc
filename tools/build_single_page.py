"""Build self-contained HTML files of the student website, to upload to the MOOC's own web server.

    python tools/build_single_page.py

    upload/new_mooc.html          ->  https://mooc.cloudearthi.com/new_mooc.html     (the student website)
    upload/award.html             ->  https://mooc.cloudearthi.com/award.html        (each certificate/badge;
                                                                                      its verification address)
    upload/profile.html           ->  https://mooc.cloudearthi.com/profile.html      (a student's awards)

Upload all three, with these names, into the same folder. Stylesheets, scripts and images are put inside the files; the fonts come from
Google Fonts and the data from the MOOC database, as on GitHub Pages.
"""
import base64
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
UPLOAD = ROOT / "upload"
PUBLIC = "https://mooc.cloudearthi.com/"          # where the three files are uploaded
SITE_FILE = "new_mooc.html"                         # the name the student website has there


def data_uri(path: pathlib.Path) -> str:
    return "data:image/png;base64," + base64.b64encode(path.read_bytes()).decode("ascii")


def inline_common(html: str) -> str:
    logo, icon = data_uri(DOCS / "assets" / "logo.png"), data_uri(DOCS / "assets" / "favicon.png")
    html = html.replace('src="assets/logo.png"', f'src="{logo}"')
    html = html.replace('href="assets/favicon.png"', f'href="{icon}"').replace('href="assets/apple-touch-icon.png"', f'href="{icon}"')
    return html


def site() -> str:
    html = (DOCS / "index.html").read_text(encoding="utf-8")
    css = (DOCS / "assets" / "site.css").read_text(encoding="utf-8")
    js = (DOCS / "assets" / "site.js").read_text(encoding="utf-8")
    js = js.replace('"award.html?id=', f'"{PUBLIC}award.html?id=').replace('`award.html?id=', f'`{PUBLIC}award.html?id=')
    js = js.replace('href="award.html?id=', f'href="{PUBLIC}award.html?id=').replace('href="profile.html?u=', f'href="{PUBLIC}profile.html?u=')
    if re.search(r'(?<![/\w])(award|profile)\.html', js):
        raise SystemExit("a relative award/profile link is left in site.js")
    js = js.replace("</script", "<\\/script")
    html = html.replace('<link rel="stylesheet" href="assets/site.css">', f"<style>\n{css}\n</style>")
    html = html.replace('<script src="assets/site.js"></script>', f"<script>\n{js}\n</script>")
    return inline_common(html)


def award_or_profile(name: str) -> str:
    html = (DOCS / name).read_text(encoding="utf-8")
    cert = (DOCS / "assets" / "certificate.js").read_text(encoding="utf-8").replace("</script", "<\\/script")
    html = html.replace('<script src="assets/certificate.js"></script>', f"<script>\n{cert}\n</script>")
    html = html.replace('href="index.html"', f'href="{SITE_FILE}"')   # back to the student website
    return inline_common(html)


def main():
    UPLOAD.mkdir(exist_ok=True)
    for out, html in ((SITE_FILE, site()), ("award.html", award_or_profile("award.html")),
                      ("profile.html", award_or_profile("profile.html"))):
        if "assets/" in html:
            raise SystemExit(f"{out}: a link to assets/ is left in the page")
        if 'href="index.html"' in html:
            raise SystemExit(f"{out}: a link to index.html is left in the page")
        path = UPLOAD / out
        path.write_text(html, encoding="utf-8")
        print(f"{path.relative_to(ROOT)}: {path.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
