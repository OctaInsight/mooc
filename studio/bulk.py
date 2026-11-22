"""Issue certificates and badges to a list of people, and email each person their own certificate.

Used for courses with little or no content, conferences and workshops. The list comes from an Excel or CSV file with
the columns First name, Last name (or Name), Email and, optionally, Contribution (printed on the certificate).
People need no Octa account; when one exists with the same email, the award also shows on their profile.
"""
from __future__ import annotations

import datetime as dt
import html
import io
import re
from urllib.parse import quote
import time

import pandas as pd
import streamlit as st

import mooc_db as db
from mooc_db import MoocError
from octa_auth import mail

SITE = "https://octainsight.github.io/mooc/"
AWARD_PAGE = SITE + "award.html?id="
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
STOP_WORDS = ("limit", "not set up", "API key", "sender", "email settings", "Could not reach")
DAILY_EMAILS = 100          # Resend free plan, shared by all Octa apps
COLUMNS = {                 # accepted column names (compared without spaces, dots, dashes or case)
    "first": ("firstname", "givenname", "first", "forename", "prenom", "vorname"),
    "last": ("lastname", "familyname", "surname", "last", "nom", "nachname"),
    "name": ("name", "fullname", "participant", "student", "attendee"),
    "email": ("email", "emailaddress", "mail", "epost", "courriel"),
    "contribution": ("contribution", "role", "participation", "contributionrole", "as"),
}


def award_url(award_id: str) -> str:
    try:
        base = st.secrets.get("mooc", {}).get("award_page") or AWARD_PAGE
    except Exception:
        base = AWARD_PAGE
    return f"{base}{award_id}"


def linkedin_url(award_id: str) -> str:
    return "https://www.linkedin.com/sharing/share-offsite/?url=" + quote(award_url(award_id), safe="")


def site_url() -> str:
    try:
        return st.secrets.get("mooc", {}).get("site") or SITE
    except Exception:
        return SITE


# ------------------------------------------------------------------------------------------------ reading the list
def template_xlsx() -> bytes:
    df = pd.DataFrame([
        {"First name": "Maria", "Last name": "Okafor", "Email": "maria.okafor@example.org", "Contribution": "Keynote speaker"},
        {"First name": "Lars", "Last name": "Berg", "Email": "lars.berg@example.org", "Contribution": ""},
    ])
    buf = io.BytesIO()
    with pd.ExcelWriter(buf, engine="openpyxl") as xw:
        df.to_excel(xw, index=False, sheet_name="People")
        ws = xw.sheets["People"]
        for col, width in zip("ABCD", (18, 22, 34, 34)):
            ws.column_dimensions[col].width = width
    return buf.getvalue()


def _key(col) -> str:
    return re.sub(r"[^a-z]", "", str(col).lower())


def read_people(upload) -> tuple[list[dict], list[str]]:
    """Rows {name, email, contribution, line} from an uploaded Excel or CSV file, and problems found."""
    name = upload.name.lower()
    try:
        if name.endswith((".xlsx", ".xlsm")):
            df = pd.read_excel(upload, dtype=str)
        else:
            raw = upload.getvalue()
            text = raw.decode("utf-8-sig", errors="replace")
            sep = ";" if text.count(";") > text.count(",") else ","
            df = pd.read_csv(io.StringIO(text), dtype=str, sep=sep)
    except Exception as e:  # noqa: BLE001 - shown to the user
        return [], [f"The file could not be read ({type(e).__name__}). Save it as .xlsx or .csv and try again."]
    found = {}
    for col in df.columns:
        k = _key(col)
        for field, names in COLUMNS.items():
            if field not in found and k in names:
                found[field] = col
    if "email" not in found or not ({"name", "first"} & set(found)):
        return [], ["The file needs an Email column and either a Name column or First name and Last name columns. "
                    f"Columns found: {', '.join(map(str, df.columns)) or 'none'}. Download the template to see the layout."]
    rows, problems, seen = [], [], set()
    for i, rec in df.fillna("").iterrows():
        line = i + 2                                               # line number as seen in Excel (after the header)
        get = lambda f: str(rec[found[f]]).strip() if f in found else ""   # noqa: E731
        full = " ".join(x for x in (get("first"), get("last")) if x) or get("name")
        email = get("email").lower()
        if not full and not email:
            continue                                               # empty line
        if not full:
            problems.append(f"Line {line}: no name ({email}).")
            continue
        if not EMAIL_RE.match(email):
            problems.append(f"Line {line}: {full} has no valid email ({email or 'empty'}).")
            continue
        if email in seen:
            problems.append(f"Line {line}: {email} is listed twice; the first line is used.")
            continue
        seen.add(email)
        rows.append({"name": full, "first_name": get("first"), "last_name": get("last"), "email": email,
                     "contribution": get("contribution"), "line": line})
    return rows, problems


# ------------------------------------------------------------------------------------------------ emails
def _email_one(person: dict, awards: list[dict], course: dict, message: str, account: dict | None = None) -> None:
    """One email per person: what they received, for which course, how to view and share it, and how to sign in.
    New accounts get the set-password link as the main button; existing accounts are reminded of their password
    and given a link to choose a new one."""
    certs = [a for a in awards if a["kind"] == "certificate"]
    what = "certificate" if certs and len(awards) == 1 else "badge" if len(awards) == 1 else "certificate and badges" if certs else "badges"
    e = lambda s: html.escape(str(s), quote=False)   # noqa: E731
    site = site_url()
    names = " and ".join(f"<b>{e(a['title'])}</b>" for a in awards)
    event = course.get("kind") == "event"
    paragraphs = [f"Dear {e(person['name'])},",
                  f"Congratulations! You have received the {what} {names} for "
                  f"{'' if event else 'the course '}<b>{e(course['title'])}</b>."]
    if message.strip():
        paragraphs.append(e(message.strip()).replace("\n", "<br>"))
    shares = [f"{e(a['title'])}: <a href='{award_url(a['award_id'])}'>view and download</a> · "
              f"<a href='{linkedin_url(a['award_id'])}'>share on LinkedIn</a>" for a in awards]
    token = (account or {}).get("set_password_token")
    subject = f"Your {what}: {course['title']}"
    if token:
        paragraphs.append("We have created a free CloudEARTHi MOOC account for you, where the course and your "
                          f"{what} are kept, together with your public profile. Your username is "
                          f"<b>{e(account['username'])}</b>; you can also sign in with this email address.")
        paragraphs.append(f"To open your account, choose a password with the button below (the link works for 30 days). "
                          f"Then sign in at any time at <a href='{site}'>{site}</a> and open <b>My learning</b>.")
        after = [f"Each {'one' if len(awards) > 1 else what} also has its own page with your name, which you can "
                 "download, add to your LinkedIn profile and share on social media:"] + shares
        mail.send(person["email"], subject, paragraphs, button=("Set your password", f"{site}#/welcome?t={token}"), after=after)
        return
    if account:                                            # an existing Octa account: it is on their profile now
        paragraphs.append(f"It has been added to your CloudEARTHi MOOC profile, and {'the event' if event else 'the course'} "
                          "is listed under <b>My learning</b>. Sign in at "
                          f"<a href='{site}#/signin?next=/my'>{site}</a> with your email or username "
                          f"(<b>{e(account['username'])}</b>) and your usual Octa password, the same one you use for the "
                          "other Octa Insight apps.")
        paragraphs.append("Forgot your password? <a href='"
                          f"{site}#/forgot?email={quote(person['email'])}'>Choose a new one here</a>.")
    else:
        paragraphs.append("Each one has its own page with your name, where you can download it and share it on "
                          "LinkedIn and other social media. The page also lets anyone check that it is genuine.")
    first = awards[0]
    mail.send(person["email"], subject, paragraphs,
              button=(f"View and share your {'certificate' if first['kind'] == 'certificate' else 'badge'}",
                      award_url(first["award_id"])),
              after=shares)


def invite(course: dict, people: list[dict]) -> dict[str, dict]:
    """Enrol everyone as a student of the course, creating accounts for new people. {email: {username, set_password_token}}"""
    if not people:
        return {}
    r = db.manage("invite_students", course_id=course["id"],
                  rows=[{k: p.get(k, "") for k in ("name", "first_name", "last_name", "email")} for p in people])
    return {x["email"]: x for x in r["people"]}


def send_emails(awards: list[dict], course: dict, message: str = "",
                accounts: dict[str, dict] | None = None) -> tuple[int, int, str | None]:
    """Email the people behind these awards (one email per person). Returns (sent, failed, reason it stopped)."""
    people: dict[str, dict] = {}
    for a in awards:
        if a.get("email"):
            people.setdefault(a["email"], {"name": a["name"], "email": a["email"], "awards": []})["awards"].append(a)
    if not people:
        return 0, 0, None
    if accounts is None:                                   # sending later: fresh set-password links for new accounts
        try:
            accounts = invite(course, list(people.values()))
        except MoocError:
            accounts = {}
    sent = failed = 0
    stopped = None
    bar = st.progress(0.0, text="Sending emails…")
    for n, p in enumerate(people.values(), 1):
        ids = [a["award_id"] for a in p["awards"]]
        try:
            _email_one(p, p["awards"], course, message, accounts.get(p["email"]))
            db.manage("award_email", ids=ids, sent=True)
            sent += 1
        except mail.MailError as err:
            failed += 1
            db.manage("award_email", ids=ids, sent=False, error=str(err))
            if any(w in str(err) for w in STOP_WORDS):            # the same for everyone: stop instead of failing each
                stopped = str(err)
                rest = [a["award_id"] for q in list(people.values())[n:] for a in q["awards"]]
                if rest:
                    db.manage("award_email", ids=rest, sent=False, error=str(err))
                    failed += len(people) - n
                break
        bar.progress(n / len(people), text=f"Sending emails… {n} of {len(people)}")
        time.sleep(0.55)                                   # stay under Resend's 2 emails per second
    bar.empty()
    return sent, failed, stopped


# ------------------------------------------------------------------------------------------------ the tab
def tab_issue(c: dict, flash) -> None:
    st.caption("Give this course's certificate and badges to a list of people, each with their own name and "
               "contribution, and email everyone the link to their certificate. Useful for conferences, workshops "
               "and courses with little content. Everyone on the list becomes a student of this course; people "
               "without an Octa account get one, and their email asks them to choose a password.")
    badges = [b for b in c["badges"] if b.get("active", True)]
    if not badges:
        st.info("First create the certificate and/or badges in the **Badges & certificates** tab (title and design). "
                "Then come back here to issue them.")
        _issued_list(c)
        return

    st.markdown("#### 1. The list of people")
    a, b = st.columns([3, 1])
    with a:
        up = st.file_uploader("Excel or CSV file", type=["xlsx", "csv"], key=f"bulk_file_{c['id']}",
                              help="Columns: First name, Last name, Email, and optionally Contribution (e.g. Speaker, "
                                   "Participant, Attended both days). A single Name column also works.")
    b.write("")
    b.download_button("Download the template", template_xlsx(), "certificates_template.xlsx",
                      mime="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
    if up is None:
        _issued_list(c)
        return
    rows, problems = read_people(up)
    if problems:
        with st.expander(f"⚠️ {len(problems)} line{'s' * (len(problems) != 1)} skipped", expanded=not rows):
            for p in problems[:200]:
                st.write(p)
    if not rows:
        _issued_list(c)
        return

    st.markdown("#### 2. What to give them")
    labels = {x["id"]: ("📜 " if x["kind"] == "certificate" else "🏅 ") + x["title"] for x in badges}
    default = [x["id"] for x in badges if x["kind"] == "certificate"][:1] or [badges[0]["id"]]
    with st.form(f"bulk_{c['id']}"):
        chosen = st.multiselect("Certificate and/or badges", list(labels), default=default, format_func=labels.get)
        x, y = st.columns(2)
        day = x.date_input("Date on the certificate", dt.date.today(), format="DD.MM.YYYY",
                           help="For a conference or workshop, the date it took place.")
        dflt = y.text_input("Contribution for people without one in the file", placeholder="Participant",
                            help="Printed on the certificate, e.g. Participant. Leave empty to print none.")
        send = st.checkbox("Email each person their certificate (and, for new accounts, a link to choose a password)", True)
        msg = st.text_area("A few words for the email (optional)", height=80,
                           placeholder="Thank you for taking part in the workshop in Oslo.")
        preview = pd.DataFrame([{"Line": r["line"], "Name": r["name"], "Email": r["email"],
                                 "Contribution": r["contribution"] or dflt or ""} for r in rows])
        st.dataframe(preview, hide_index=True, width="stretch", height=min(38 * (len(rows) + 1), 360))
        if send and len(rows) > DAILY_EMAILS - 5:
            st.warning(f"The email service sends at most {DAILY_EMAILS} emails a day for all Octa apps together. "
                       "Emails that cannot go today can be sent tomorrow with **Send emails not yet sent** below.")
        go = st.form_submit_button(f"Issue to {len(rows)} {'person' if len(rows) == 1 else 'people'}", type="primary")
    if not go:
        _issued_list(c)
        return
    if not chosen:
        st.error("Choose at least one certificate or badge.")
        return
    try:
        accounts = invite(c, rows)                         # first, so the awards are tied to the accounts
        r = db.manage("bulk_award", badge_ids=chosen, issued_at=day.isoformat() + "T12:00:00Z",
                      default_contribution=dflt.strip(), rows=[{k: v for k, v in r.items() if k != "line"} for r in rows])
    except MoocError as e:
        st.error(str(e))
        return
    awards = r["awards"]
    new = [a for a in awards if a["new"]]
    msg_parts = [f"Issued {len(new)} award{'s' * (len(new) != 1)}."]
    if len(awards) > len(new):
        msg_parts.append(f"{len(awards) - len(new)} already existed and were left as they were.")
    made = sum(1 for x in accounts.values() if x["created"])
    msg_parts.append(f"All {len(accounts)} are students of this course" + (f"; {made} new account{'s' * (made != 1)} created." if made else "."))
    if send:
        todo = [a for a in awards if a["new"] or not a.get("email_sent_at")]
        sent, failed, stopped = send_emails(todo, c, msg, accounts)
        msg_parts.append(f"Emails sent: {sent}." + (f" Not sent: {failed}." if failed else ""))
        if stopped:
            msg_parts.append(stopped)
    flash("success" if not (send and failed) else "warning", " ".join(msg_parts))
    st.rerun()


def _issued_list(c: dict) -> None:
    st.markdown("#### Issued certificates and badges")
    try:
        awards = db.manage("awards", course_id=c["id"])["awards"]
    except MoocError as e:
        st.error(str(e))
        return
    if not awards:
        st.caption("Nothing issued yet.")
        return
    def status(a):
        if a["revoked"]:
            return "withdrawn"
        if a["email_sent_at"]:
            return "sent " + a["email_sent_at"][:10]
        if a["email_error"]:
            return "not sent: " + a["email_error"][:60]
        return "not sent" if a["source"] == "bulk" else "earned in the course"
    df = pd.DataFrame([{"Name": a["name"], "Email": a["email"], "Award": a["title"], "Contribution": a["contribution"] or "",
                        "Date": a["issued_at"][:10], "Email status": status(a), "Link": award_url(a["award_id"])} for a in awards])
    st.dataframe(df, hide_index=True, width="stretch", height=min(38 * (len(df) + 1), 420),
                 column_config={"Link": st.column_config.LinkColumn("Certificate page", display_text="open")})
    unsent = [a for a in awards if a["source"] == "bulk" and not a["revoked"] and not a["email_sent_at"] and a.get("email")]
    x, y, z = st.columns(3)
    if unsent and x.button(f"Send emails not yet sent ({len({a['email'] for a in unsent})} people)", key=f"resend_{c['id']}"):
        sent, failed, stopped = send_emails(unsent, c)
        st.success(f"Emails sent: {sent}." + (f" Not sent: {failed}. {stopped or ''}" if failed else ""))
        st.rerun()
    buf = io.BytesIO()
    df.to_excel(buf, index=False, engine="openpyxl")
    y.download_button("Download this list (Excel)", buf.getvalue(), f"{c['slug']}_certificates.xlsx",
                      mime="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", key=f"dl_{c['id']}")
    with z.popover("Withdraw or restore"):
        pick = st.selectbox("Award", [a["award_id"] for a in awards], key=f"wd_{c['id']}",
                            format_func=lambda i: next(f"{a['name']}: {a['title']}{' (withdrawn)' if a['revoked'] else ''}"
                                                       for a in awards if a["award_id"] == i))
        cur = next(a for a in awards if a["award_id"] == pick)
        st.caption("A withdrawn award shows as withdrawn on its page, so it can no longer be used as proof.")
        if st.button("Restore" if cur["revoked"] else "Withdraw", key=f"wdb_{c['id']}"):
            try:
                db.manage("revoke_award", id=pick, revoked=not cur["revoked"])
                st.rerun()
            except MoocError as e:
                st.error(str(e))
