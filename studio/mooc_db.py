"""Calls to the MOOC database functions (mooc_*) and file uploads to the 'mooc' storage bucket.

Uses the same settings and HTTPS connection as octa_auth (Streamlit secrets, section [octa_users]).
Every call carries the user's Octa session token; the database checks the user's MOOC role itself.
"""
from __future__ import annotations
import re
import uuid

from octa_auth import client, token


class MoocError(RuntimeError):
    pass


def manage(action: str, **args) -> dict:
    """One call to mooc_manage. Raises MoocError with a readable message when the answer is not ok."""
    try:
        r = client.rpc("mooc_manage", p_token=token(), p={"action": action, **args})
    except client.OctaError as e:
        raise MoocError(str(e)) from None
    if not r or not r.get("ok"):
        raise MoocError((r or {}).get("error") or "The MOOC database refused this.")
    return r


# ------------------------------------------------------------------------------------------------ uploads
_SAFE = re.compile(r"[^A-Za-z0-9._-]+")


def public_url(path: str) -> str:
    return f"{client.setting('url').rstrip('/')}/storage/v1/object/public/mooc/{path}"


def upload(data: bytes, filename: str, content_type: str) -> str:
    """Upload a file (PDF or image) and return its public address. Needs a one-time ticket from the database,
    which only teachers and admins get; the storage policy checks the ticket."""
    ticket = manage("upload_ticket")["ticket"]
    name = _SAFE.sub("-", filename).strip("-")[-80:] or "file"
    path = f"{ticket}/{uuid.uuid4().hex[:8]}-{name}"
    key = client.setting("key")
    r = client._http().post(f"{client.setting('url').rstrip('/')}/storage/v1/object/mooc/{path}", data=data, timeout=120,
                            headers={"apikey": key, "Authorization": f"Bearer {key}", "Content-Type": content_type,
                                     "x-upsert": "false"})
    if r.status_code >= 400:
        raise MoocError(f"The file could not be uploaded ({r.status_code}). {r.text[:200]}")
    return public_url(path)


# ------------------------------------------------------------------------------------------------ helpers
_YT = re.compile(r"(?:youtu\.be/|youtube\.com/(?:watch\?(?:.*&)?v=|embed/|shorts/|live/))([A-Za-z0-9_-]{11})")


def youtube_id(text: str) -> str | None:
    """YouTube video id from a link or a bare id."""
    text = (text or "").strip()
    if re.fullmatch(r"[A-Za-z0-9_-]{11}", text):
        return text
    m = _YT.search(text)
    return m.group(1) if m else None


def mmss(seconds) -> str:
    s = int(seconds or 0)
    return f"{s // 60}:{s % 60:02d}"


def parse_mmss(text: str) -> int | None:
    """'1:30' -> 90, '90' -> 90, '' -> None."""
    text = (text or "").strip()
    if not text:
        return None
    if re.fullmatch(r"\d+", text):
        return int(text)
    m = re.fullmatch(r"(\d+)\s*[:.,m]\s*([0-5]?\d)\s*s?", text)
    if not m:
        raise ValueError("Write the time as minutes:seconds, for example 1:30.")
    return int(m.group(1)) * 60 + int(m.group(2))


def slugify(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", (text or "").lower()).strip("-")[:60]
