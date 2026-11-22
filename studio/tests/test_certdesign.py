"""Certificates on the course's own design."""
import io
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import certdesign  # noqa: E402


def _png(w, h, color="white"):
    b = io.BytesIO()
    Image.new("RGB", (w, h), color).save(b, "PNG")
    return b.getvalue()


def test_png_and_pdf_designs_become_images():
    data, name, ctype, w, h = certdesign.to_image(_png(4961, 3508), "design.png")      # A4 landscape at 600 dpi
    assert (name, ctype) == ("certificate.png", "image/png") and max(w, h) == certdesign.LONG_SIDE and round(w / h, 2) == 1.41
    pdf = io.BytesIO()
    Image.new("RGB", (595, 842), "#e8f3dd").save(pdf, "PDF")                            # A4 portrait PDF
    data, name, ctype, w, h = certdesign.to_image(pdf.getvalue(), "Funder design.PDF")
    assert ctype == "image/png" and h == certdesign.LONG_SIDE and w < h
    px = Image.open(io.BytesIO(data)).getpixel((10, 10))[:3]
    assert all(abs(a - b) <= 3 for a, b in zip(px, (232, 243, 221))), px       # PDF compression may shift a shade


def test_details_can_be_added_and_removed_keeping_their_places():
    tpl = {"fields": [{"key": "name", **certdesign.DEFAULTS["name"], "x": .3}]}
    certdesign._sync_fields(tpl, ["name", "contribution"])
    assert [f["key"] for f in tpl["fields"]] == ["name", "contribution"] and tpl["fields"][0]["x"] == .3
    certdesign._sync_fields(tpl, ["contribution"])
    assert [f["key"] for f in tpl["fields"]] == ["contribution"]


def test_preview_draws_the_details_where_placed(monkeypatch):
    monkeypatch.setattr(certdesign, "_download", lambda url: _png(2000, 1414))
    tpl = {"image_url": "https://x/c.png", "width": 2000, "height": 1414,
           "fields": [{"key": "name", **certdesign.DEFAULTS["name"], "x": .25, "y": .5, "color": "#ff0000"}]}
    im = certdesign.preview_image(tpl, {"name": "Maria Okafor"}, "name")
    assert im.width == certdesign.PREVIEW_W
    red = [(x, y) for x in range(0, im.width, 2) for y in range(0, im.height, 2) if im.getpixel((x, y))[0] > 200 and im.getpixel((x, y))[1] < 80]
    xs = [x for x, _ in red]
    assert red and abs(sum(xs) / len(xs) - im.width * .25) < im.width * .08     # the name is centred near 25 % across
