"""Certificates on a course's own design (funders' and partners' logos, the project's look).

The teacher or course admin uploads the design as PNG, JPG or PDF (the first page of a PDF is turned into an image),
picks which details to write on it (the student's name, the contribution, the course, the date, the verification
address), clicks on the picture where each goes, and adjusts size, colour and font. The award page then draws the
certificate exactly so (docs/assets/certificate.js); the preview here uses the same code.
"""
from __future__ import annotations

import copy
import datetime as dt
import io
import json
from pathlib import Path

import requests
import streamlit as st
import streamlit.components.v1 as components
from PIL import Image, ImageDraw, ImageFont

import links
import mooc_db as db
from mooc_db import MoocError

FIELDS = {
    "name": "Student's name", "contribution": "Contribution (e.g. Keynote speaker)", "course": "Course or event title",
    "title": "Certificate title", "date": "Date", "verify": "Verification address",
}
DEFAULTS = {
    "name": dict(x=.5, y=.45, size=.05, font="serif", bold=False, italic=True, color="#0b0b0b", align="center", prefix="", max=.8),
    "contribution": dict(x=.5, y=.55, size=.025, font="sans", bold=True, italic=False, color="#0b0b0b", align="center", prefix="", max=.8),
    "course": dict(x=.5, y=.62, size=.03, font="sans", bold=True, italic=False, color="#0b0b0b", align="center", prefix="", max=.85),
    "title": dict(x=.5, y=.3, size=.04, font="serif", bold=True, italic=False, color="#0b0b0b", align="center", prefix="", max=.85),
    "date": dict(x=.3, y=.82, size=.02, font="sans", bold=False, italic=False, color="#0b0b0b", align="center", prefix="", max=.4),
    "verify": dict(x=.5, y=.94, size=.012, font="sans", bold=False, italic=False, color="#52514e", align="center", prefix="", max=.9),
}
DEFAULT_ON = ["name", "contribution", "date", "verify"]
LONG_SIDE = 3000             # pixels: sharp when printed on A4, small enough to load quickly
PREVIEW_W = 900
CERT_JS = Path(__file__).resolve().parent.parent / "docs" / "assets" / "certificate.js"


# ------------------------------------------------------------------------------------------------ files
def to_image(data: bytes, filename: str) -> tuple[bytes, str, str, int, int]:
    """The design as (bytes, file name, content type, width, height). A PDF's first page becomes a PNG."""
    if filename.lower().endswith(".pdf"):
        import pypdfium2 as pdfium
        pdf = pdfium.PdfDocument(data)
        if len(pdf) == 0:
            raise ValueError("The PDF has no pages.")
        page = pdf[0]
        w, h = page.get_size()
        im = page.render(scale=LONG_SIDE / max(w, h)).to_pil()
    else:
        im = Image.open(io.BytesIO(data))
        im.load()
    im = im.convert("RGBA") if im.mode in ("RGBA", "LA", "P") else im.convert("RGB")
    if max(im.size) > LONG_SIDE:
        im.thumbnail((LONG_SIDE, LONG_SIDE), Image.LANCZOS)
    out = io.BytesIO()
    im.save(out, "PNG", optimize=True)
    if out.tell() <= 8_000_000:
        return out.getvalue(), "certificate.png", "image/png", *im.size
    out = io.BytesIO()                                  # a very detailed design: JPEG keeps the award page quick
    im.convert("RGB").save(out, "JPEG", quality=92)
    return out.getvalue(), "certificate.jpg", "image/jpeg", *im.size


@st.cache_data(show_spinner=False, max_entries=20)
def _download(url: str) -> bytes:
    r = requests.get(url, timeout=30)
    r.raise_for_status()
    return r.content


# ------------------------------------------------------------------------------------------------ preview
def sample_values(c: dict, b: dict) -> dict:
    return {"name": "Maria Okafor", "contribution": "Keynote speaker", "course": c["title"], "title": b["title"],
            "date": dt.date.today().strftime("%-d %B %Y"), "verify": f"Verified by CloudEARTHi MOOC · Octa Insight · {links.award_url('1a2b3c4d-…')}"}


def _font(px: int):
    try:
        return ImageFont.load_default(size=px)
    except TypeError:                                   # an old Pillow without sized default fonts
        return ImageFont.load_default()


def preview_image(tpl: dict, values: dict, selected: str | None) -> Image.Image:
    """The design with the details written on it (in a plain font) and the chosen one framed in blue, for clicking."""
    im = Image.open(io.BytesIO(_download(tpl["image_url"]))).convert("RGB")
    im.thumbnail((PREVIEW_W, PREVIEW_W * 3), Image.LANCZOS)
    W, H = im.size
    d = ImageDraw.Draw(im)
    for f in tpl["fields"]:
        text = (f.get("prefix") or "") + (values.get(f["key"]) or "")
        if not text:
            continue
        px = max(6, round(f.get("size", .04) * W))
        font = _font(px)
        while d.textlength(text, font=font) > f.get("max", .85) * W and px > 6:
            px -= max(1, round(px * .05))
            font = _font(px)
        anchor = {"left": "lm", "right": "rm"}.get(f.get("align"), "mm")
        x, y = f.get("x", .5) * W, f.get("y", .5) * H
        d.text((x, y), text, fill=f.get("color", "#0b0b0b"), font=font, anchor=anchor)
        if f["key"] == selected:
            box = d.textbbox((x, y), text, font=font, anchor=anchor)
            d.rectangle((box[0] - 6, box[1] - 6, box[2] + 6, box[3] + 6), outline="#2a78d6", width=3)
            d.line((x - 10, y, x + 10, y), fill="#2a78d6", width=2)
            d.line((x, y - 10, x, y + 10), fill="#2a78d6", width=2)
    return im


def exact_preview(tpl: dict, values: dict) -> None:
    """The certificate as the award page draws it (same code, same fonts)."""
    if not CERT_JS.exists():
        st.caption("The exact preview is not available here.")
        return
    W, H = tpl.get("width") or 2000, tpl.get("height") or 1414
    height = int(min(860 * H / W, 1300)) + 24
    components.html(f"""
<link href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,400;0,600;0,700;1,400;1,500;1,700&family=Inter:ital,wght@0,400;0,600;0,700;1,400;1,700&display=swap" rel="stylesheet">
<canvas id="cv" style="width:100%;height:auto;border:1px solid #e4e3df;border-radius:6px"></canvas>
<script>{CERT_JS.read_text(encoding="utf-8")}</script>
<script>
(async () => {{
  const tpl = {json.dumps(tpl)}, values = {json.dumps(values)};
  try {{ await document.fonts.load('italic 400 40px "Cormorant Garamond"'); await document.fonts.load('700 40px Inter'); await document.fonts.ready; }} catch (e) {{}}
  const im = new Image(); im.crossOrigin = "anonymous";
  im.onload = () => drawTemplateCertificate(document.getElementById("cv"), im, tpl, values);
  im.src = tpl.image_url;
}})();
</script>""", height=height)


# ------------------------------------------------------------------------------------------------ editor
def _sync_fields(tpl: dict, keys: list[str]) -> None:
    have = {f["key"]: f for f in tpl["fields"]}
    tpl["fields"] = [have.get(k) or {"key": k, **DEFAULTS[k]} for k in keys]


def editor(c: dict, b: dict, run) -> None:
    from streamlit_image_coordinates import streamlit_image_coordinates

    S, bid = st.session_state, b["id"]
    key = f"tpl_{bid}"
    if key not in S:
        S[key] = copy.deepcopy(b.get("template"))
    tpl = S[key]

    own = st.radio("Design", ["standard", "own"], index=1 if tpl else 0, horizontal=True, key=f"tplmode_{bid}",
                   format_func=lambda m: "Standard CloudEARTHi design" if m == "standard" else
                   "Our own design (with our funders' and partners' logos)")
    if own == "standard":
        if b.get("template"):
            st.caption("This certificate uses your own design now.")
            if st.button("Use the standard design again", key=f"tplstd_{bid}"):
                if run("save_badge", "The standard design is used again.", id=bid, template=None):
                    S.pop(key, None)
                    st.rerun()
        else:
            st.caption("Certificates use the standard CloudEARTHi design, with the student's name, the course, the "
                       "contribution, the date and the verification address.")
        return

    up = st.file_uploader("The certificate design: PNG, JPG or PDF (the first page is used). Leave empty space where "
                          "the student's name and the other details go.", type=["png", "jpg", "jpeg", "pdf"], key=f"tplup_{bid}")
    if up is not None and S.get(f"tplupdone_{bid}") != (up.name, up.size):
        try:
            data, name, ctype, w, h = to_image(up.getvalue(), up.name)
            url = db.upload(data, name, ctype)
        except (MoocError, ValueError, OSError) as e:
            st.error(f"The design could not be used: {e}")
            return
        except Exception as e:  # noqa: BLE001 - a broken file
            st.error(f"The file could not be read as an image or PDF ({type(e).__name__}).")
            return
        fields = tpl["fields"] if tpl else [{"key": k, **DEFAULTS[k]} for k in DEFAULT_ON]
        S[key] = tpl = {"image_url": url, "width": w, "height": h, "fields": fields}
        S[f"tplupdone_{bid}"] = (up.name, up.size)
        st.success("Design uploaded. Now place the details and save.")
    if not tpl:
        st.info("Upload your design to start.")
        return

    keys = st.multiselect("Details written on the certificate", list(FIELDS), default=[f["key"] for f in tpl["fields"]],
                          format_func=FIELDS.get, key=f"tplkeys_{bid}")
    _sync_fields(tpl, keys)
    if not keys:
        st.warning("Choose at least the student's name.")
        return
    sel = st.radio("Place this detail", keys, format_func=FIELDS.get, horizontal=True, key=f"tplsel_{bid}")
    f = next(x for x in tpl["fields"] if x["key"] == sel)
    values = sample_values(c, b)
    st.caption(f"Click on the picture where the **middle of the {FIELDS[sel].split(' (')[0].lower()}** should be. "
               "The blue frame shows it. The example text uses a plain font; the exact look is in the preview below.")
    try:
        img = preview_image(tpl, values, sel)
    except Exception as e:  # noqa: BLE001
        st.error(f"The design could not be loaded ({type(e).__name__}). Upload it again.")
        return
    click = streamlit_image_coordinates(img, key=f"tplclick_{bid}", width=img.width)
    stamp = (click or {}).get("unix_time") or (click and (click["x"], click["y"]))
    if click and stamp != S.get(f"tplstamp_{bid}"):
        S[f"tplstamp_{bid}"] = stamp
        f["x"] = round(click["x"] / click["width"], 4)
        f["y"] = round(click["y"] / click["height"], 4)
        st.rerun()

    a, b2, c3, d = st.columns(4)
    f["size"] = a.slider("Text size", 0.5, 12.0, round(f["size"] * 100, 1), 0.1, key=f"tplsz_{bid}_{sel}",
                         help="Height of the letters, as a percentage of the design's width.") / 100
    f["color"] = b2.color_picker("Colour", f["color"], key=f"tplcol_{bid}_{sel}")
    f["font"] = c3.selectbox("Font", ["serif", "sans"], index=0 if f["font"] == "serif" else 1, key=f"tplfont_{bid}_{sel}",
                             format_func=lambda x: "Elegant (Cormorant Garamond)" if x == "serif" else "Plain (Inter)")
    f["align"] = d.selectbox("Line up", ["center", "left", "right"], index=["center", "left", "right"].index(f["align"]),
                             key=f"tplal_{bid}_{sel}", format_func={"center": "Centred on the point", "left": "Starts at the point",
                                                                    "right": "Ends at the point"}.get)
    a, b2, c3, d = st.columns(4)
    f["bold"] = a.checkbox("Bold", f["bold"], key=f"tplb_{bid}_{sel}")
    f["italic"] = a.checkbox("Italic", f["italic"], key=f"tpli_{bid}_{sel}")
    f["prefix"] = b2.text_input("Text before it", f.get("prefix", ""), key=f"tplpre_{bid}_{sel}",
                                placeholder="e.g. as " if sel == "contribution" else "", max_chars=60)
    f["max"] = c3.slider("Widest (% of width)", 10, 100, int(f.get("max", .85) * 100), 5, key=f"tplmax_{bid}_{sel}",
                         help="Long names get smaller so they never run wider than this.") / 100
    with d:
        f["x"] = st.number_input("Across (%)", 0.0, 100.0, round(f["x"] * 100, 2), 0.5, key=f"tplx_{bid}_{sel}_{f['x']}") / 100
        f["y"] = st.number_input("Down (%)", 0.0, 100.0, round(f["y"] * 100, 2), 0.5, key=f"tply_{bid}_{sel}_{f['y']}") / 100

    with st.expander("Exact preview, as students will see it", expanded=True):
        exact_preview(tpl, values)
    x, y = st.columns(2)
    if x.button("Save the certificate design", type="primary", key=f"tplsave_{bid}"):
        if run("save_badge", "Certificate design saved. Certificates already issued show it too.", id=bid, template=tpl):
            S.pop(key, None)
            st.rerun()
    if y.button("Undo my changes", key=f"tplundo_{bid}"):
        S.pop(key, None)
        st.rerun()
