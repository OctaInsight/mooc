"""Award emails, sent by MOOC Studio with the Resend settings in the Streamlit secrets (octa_auth.mail), like the
password-reset emails.

When a student earns a badge or certificate in a course (on the MOOC website, or after a teacher's grade), the
database puts the award in an outbox. MOOC Studio empties it:
  * a background thread checks every few minutes while the app is running;
  * each time someone opens MOOC Studio (any page, signed in or not);
  * with "Send now" under People -> Email.
Streamlit Cloud puts the app to sleep after a long quiet period; emails waiting then go out the next time anyone
opens MOOC Studio. Only an app holding the server key ([octa_users] server_key) can read the outbox.
"""
from __future__ import annotations

import html
import logging
import threading
import time
from urllib.parse import quote

import streamlit as st

from octa_auth import client, mail

SITE = "https://octainsight.github.io/mooc/"
EVERY = 300                       # seconds between checks in the background
STOP_WORDS = ("limit", "not set up", "API key", "sender", "email settings", "Could not reach")
_LOCK = threading.Lock()
log = logging.getLogger("mooc.outbox")


def site_url() -> str:
    try:
        return st.secrets.get("mooc", {}).get("site") or SITE
    except Exception:
        return SITE


def award_url(award_id: str) -> str:
    return f"{site_url()}award.html?id={award_id}"


def linkedin_url(award_id: str) -> str:
    return "https://www.linkedin.com/sharing/share-offsite/?url=" + quote(award_url(award_id), safe="")


def _e(s) -> str:
    return html.escape(str(s or ""), quote=False)


def email_earned(p: dict) -> None:
    """One email to a student for the awards they earned since the last email."""
    awards = p["awards"]
    site = site_url()
    certs = [a for a in awards if a["kind"] == "certificate"]
    one = len(awards) == 1
    what = ("certificate" if certs else "badge") if one else ("certificate and badges" if certs else "badges")
    courses = list(dict.fromkeys(a["course"] for a in awards))
    names = " and ".join(f"<b>{_e(a['title'])}</b>" for a in awards)
    paragraphs = [
        f"Dear {_e(p.get('name') or p['username'])},",
        f"Congratulations! You have earned the {what} {names} in "
        + " and ".join(f"<b>{_e(c)}</b>" for c in courses) + " on the CloudEARTHi MOOC.",
        f"It is on your public profile and under <b>My learning</b> at <a href='{site}#/my'>{site}</a>. Its own page "
        "shows your name, lets you download it, add it to your LinkedIn profile and share it on social media, and "
        "lets anyone check that it is genuine.",
    ]
    after = [f"{_e(a['title'])}: <a href='{award_url(a['id'])}'>view and download</a> · "
             f"<a href='{linkedin_url(a['id'])}'>share on LinkedIn</a>" for a in awards]
    after.append(f"To sign in, use your email or username (<b>{_e(p['username'])}</b>) and your Octa password. "
                 f"Forgot it? <a href='{site}#/forgot?email={quote(p['email'])}'>Choose a new password</a>.")
    subject = f'You earned the {what} "{awards[0]["title"]}"' if one else f"You earned new {what}: {', '.join(courses)}"
    label = f"View and share your {what if one else ('certificate' if certs else 'badge')}"
    mail.send(p["email"], subject, paragraphs, button=(label, award_url(awards[0]["id"])), after=after)


def run_once(limit: int = 40, pause: float = 0.6) -> dict:
    """Send up to `limit` people's waiting award emails. Safe to call from several places: one run at a time."""
    if not mail.provider():
        return {"ok": False, "error": "Email is not set up for MOOC Studio."}
    if not _LOCK.acquire(blocking=False):
        return {"ok": True, "busy": True, "sent": 0, "failed": 0}
    try:
        key = client.server_key()
        r = client.rpc("mooc_mail_claim_app", p_server_key=key, p_limit=limit)
        if not r or not r.get("ok"):
            return {"ok": False, "error": "The award outbox could not be read (check [octa_users] server_key)."}
        people = r["people"]
        sent = failed = 0
        stopped = None
        for i, p in enumerate(people):
            ids = [a["id"] for a in p["awards"]]
            try:
                email_earned(p)
                client.rpc("mooc_mail_done_app", p_server_key=key, p_ids=ids, p_ok=True)
                sent += 1
            except mail.MailError as err:
                if any(w in str(err) for w in STOP_WORDS):   # the same for everyone: put them back for later
                    stopped = str(err)
                    rest = [a["id"] for q in people[i:] for a in q["awards"]]
                    client.rpc("mooc_mail_done_app", p_server_key=key, p_ids=rest, p_ok=False, p_error=stopped, p_count=False)
                    break
                failed += 1
                client.rpc("mooc_mail_done_app", p_server_key=key, p_ids=ids, p_ok=False, p_error=str(err), p_count=True)
            time.sleep(pause)                                     # Resend allows 2 emails a second
        return {"ok": True, "people": len(people), "sent": sent, "failed": failed, "stopped": stopped}
    finally:
        _LOCK.release()


def status() -> dict:
    try:
        return client.rpc("mooc_mail_status", p_server_key=client.server_key()) or {}
    except Exception as e:  # noqa: BLE001 - shown on the People page
        return {"ok": False, "error": str(e)}


def _loop() -> None:
    while True:
        try:
            s = status()
            if s.get("ok") and s.get("pending"):
                log.info("award emails: %s", run_once())
        except Exception:  # noqa: BLE001 - keep the thread alive
            log.exception("award email run failed")
        time.sleep(EVERY)


@st.cache_resource(show_spinner=False)
def start_background() -> threading.Thread:
    """One sender thread per running app (started on the first page view)."""
    t = threading.Thread(target=_loop, name="mooc-award-emails", daemon=True)
    t.start()
    return t
