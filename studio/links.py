"""Web addresses used in MOOC Studio's emails and links, in one place.

  student website  https://mooc.cloudearthi.com/new_mooc.html   sign in, My learning, set or reset the password,
                                                                 course pages (hash links such as #/signin)
  award pages      https://mooc.cloudearthi.com/                each certificate's or badge's own page
                                                                 (award.html, profile.html: the verification address)

Either can be changed in the Streamlit secrets without new code:
  [mooc]
  site = "https://mooc.cloudearthi.com/new_mooc.html"
  pages = "https://mooc.cloudearthi.com/"
"""
from __future__ import annotations

from urllib.parse import quote

import streamlit as st

STUDENT_SITE = "https://mooc.cloudearthi.com/new_mooc.html"
AWARD_PAGES = "https://mooc.cloudearthi.com/"


def _secret(name: str) -> str:
    try:
        return str(st.secrets.get("mooc", {}).get(name) or "").strip()
    except Exception:
        return ""


def site() -> str:
    """The student website, without a trailing '#'. Hash links are added as site() + '#/signin'."""
    return (_secret("site") or STUDENT_SITE).split("#")[0]


def page(route: str) -> str:
    """A page of the student website, e.g. page('/signin') -> https://mooc.cloudearthi.com/new_mooc.html#/signin."""
    return f"{site()}#{route}"


def award_url(award_id: str) -> str:
    base = _secret("pages") or AWARD_PAGES
    return f"{base.rstrip('/')}/award.html?id={award_id}"


def linkedin_url(award_id: str) -> str:
    return "https://www.linkedin.com/sharing/share-offsite/?url=" + quote(award_url(award_id), safe="")
