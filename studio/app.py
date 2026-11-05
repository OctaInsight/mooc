"""MOOC Studio: where super admins, course admins and teachers build the CloudEARTHi MOOC.

Students never use this app; they learn on the MOOC website, which reads the same database.
"""
import html
import json

import pandas as pd
import streamlit as st

st.set_page_config(page_title="MOOC Studio", page_icon="🎓", layout="wide")

from octa_auth import App, require_login, sidebar, display_name  # noqa: E402
import mooc_db as db  # noqa: E402
from mooc_db import MoocError  # noqa: E402

APP = App(id="octa_mooc", name="MOOC Studio", family="education", url="https://cloudearthi-mooc.streamlit.app/",
          tagline="Build CloudEARTHi MOOC courses: lectures, interactive videos and PDFs, badges and certificates", icon="🎓")
VERSION = "0.1.0"

STEP_KINDS = {
    "video": ("🎬", "Video", "A YouTube video, with questions that pause it"),
    "pdf": ("📄", "PDF", "A PDF to read, with questions on chosen pages"),
    "text": ("📝", "Text", "A short reading written here"),
    "quiz": ("❓", "Quiz", "Questions; scored on the first try"),
    "assignment": ("📤", "Assignment", "Homework the student hands in"),
    "live": ("🎥", "Live session", "An online lecture or study-group meeting"),
}
LEVELS = ["", "beginner", "intermediate", "advanced"]

st.markdown("""<style>
.block-container{padding-top:1.6rem}
.mc-card{border:1px solid #e4e3df;border-radius:12px;padding:14px 16px;background:#fff;margin-bottom:6px}
.mc-card h4{margin:0 0 2px 0;font-size:1.05rem}
.mc-card p{margin:0;color:#52514e;font-size:.86rem}
.mc-pill{display:inline-block;font-size:.72rem;border-radius:9px;padding:1px 8px;margin-right:6px;border:1px solid #d9d7d1;color:#52514e}
.mc-pill.published{background:#e7f5ec;border-color:#b8e0c6;color:#1d6b3a}
.mc-pill.draft{background:#fff6e0;border-color:#f0dca8;color:#7a5b00}
.mc-pill.archived{background:#f1f0ed;color:#77756f}
.mc-muted{color:#77756f;font-size:.85rem}
</style>""", unsafe_allow_html=True)

user = require_login(APP)
if user is None:
    st.error("The Octa user database is not configured. Add the [octa_users] section to the Streamlit secrets.")
    st.stop()
with st.sidebar:
    sidebar(APP)

S = st.session_state


def flash(kind, msg):
    S["mc_flash"] = (kind, msg)


def show_flash():
    f = S.pop("mc_flash", None)
    if f:
        getattr(st, f[0])(f[1])


def run(action, ok_msg=None, **args):
    """Call the database; show the error instead of crashing. Returns the answer or None."""
    try:
        r = db.manage(action, **args)
    except MoocError as e:
        st.error(str(e))
        return None
    if ok_msg:
        flash("success", ok_msg)
    return r


def load(action, **args):
    try:
        return db.manage(action, **args)
    except MoocError as e:
        st.error(str(e))
        st.stop()


def pill(status):
    return f"<span class='mc-pill {status}'>{status}</span>"


def lines(text):
    return [x.strip() for x in (text or "").splitlines() if x.strip()]


# ================================================================================================ who am I
me = load("me")
overview = load("overview")
is_super = me["is_super"]
is_course_admin = me["is_course_admin"]

if not (is_super or me["can_edit_any"]):
    st.markdown(f"## 🎓 MOOC Studio")
    person = me.get("person") or {}
    if person.get("kind") == "teacher" and person.get("status") == "pending":
        st.info("Your request to teach on the CloudEARTHi MOOC is waiting for approval by an admin.")
    else:
        st.info("MOOC Studio is for teachers and course admins. A course admin or super admin can give you teacher "
                "rights in a course; you can also ask to become a teacher here.")
        if st.button("Ask to become a teacher", type="primary"):
            try:
                r = db.client.rpc("mooc_join", p_token=db.token(), p_kind="teacher")
                st.success("Your request was sent." if r.get("ok") else r.get("error"))
            except db.client.OctaError as e:
                st.error(str(e))
    st.stop()

with st.sidebar:
    st.divider()
    pages = ["Courses"]
    if is_super:
        pages.append("Projects")
    if is_super or is_course_admin:
        pending = overview.get("pending_teachers", 0)
        pages.append(f"People ({pending} waiting)" if pending else "People")
    page = st.radio("Go to", pages, label_visibility="collapsed", key="mc_page")
    st.caption(f"MOOC Studio {VERSION} · {'super admin' if is_super else 'course admin' if is_course_admin else 'teacher'}")

projects = overview["projects"]
project_names = {p["id"]: p["title"] for p in projects}


# ================================================================================================ courses list
def page_courses():
    st.markdown(f"## Hello, {html.escape(display_name(user))}")
    show_flash()
    courses = overview["courses"]
    if is_super:
        with st.expander("➕ New course"):
            with st.form("new_course", clear_on_submit=True):
                t = st.text_input("Course title")
                pr = st.selectbox("Project", [""] + list(project_names), format_func=lambda x: project_names.get(x, "— no project —"))
                sm = st.text_input("One-line summary")
                if st.form_submit_button("Create course", type="primary"):
                    if len(t.strip()) < 2:
                        st.error("Give the course a title.")
                    else:
                        r = run("save_course", "Course created. Add lectures, then publish it.", title=t.strip(),
                                project_id=pr, summary=sm.strip())
                        if r:
                            S["mc_course"] = r["id"]
                            st.rerun()
    if not courses:
        st.info("No courses yet." if is_super else "You are not a teacher or admin in any course yet.")
        return
    groups = {}
    for c in courses:
        groups.setdefault(c.get("project_id") or "", []).append(c)
    order = [p["id"] for p in projects if p["id"] in groups] + ([""] if "" in groups else [])
    for pid in order:
        st.markdown(f"#### {html.escape(project_names.get(pid, 'Courses without a project'))}")
        cols = st.columns(3)
        for i, c in enumerate(groups[pid]):
            with cols[i % 3]:
                st.markdown(f"<div class='mc-card'><h4>{html.escape(c['title'])}</h4>"
                            f"<p>{pill(c['status'])}<span class='mc-pill'>{c.get('my_role') or ''}</span></p>"
                            f"<p class='mc-muted' style='margin-top:6px'>{c['lectures']} lectures · {c['students']} students · "
                            f"{c['awards']} awards{' · <b>' + str(c['to_grade']) + ' to grade</b>' if c['to_grade'] else ''}</p></div>",
                            unsafe_allow_html=True)
                if st.button("Open", key=f"open_{c['id']}", width="stretch"):
                    S["mc_course"] = c["id"]
                    st.rerun()


# ================================================================================================ one course
def page_course(cid):
    data = load("course", course_id=cid)
    c, role = data["course"], data["my_role"]
    can_manage = role in ("super", "admin")
    top = st.columns([6, 1])
    top[0].markdown(f"## {html.escape(c['title'])}")
    top[0].markdown(f"{pill(c['status'])}<span class='mc-muted'>{html.escape((c.get('project') or {}).get('title', ''))}"
                    f" · you are {'a super admin' if role == 'super' else 'the course admin' if role == 'admin' else 'a teacher'}</span>",
                    unsafe_allow_html=True)
    if top[1].button("← All courses", width="stretch"):
        S.pop("mc_course", None)
        st.rerun()
    show_flash()
    tabs = ["📚 Lectures", "🏅 Badges & certificates", "✅ Grading & students"]
    if can_manage:
        tabs += ["👥 Team", "⚙️ Course settings"]
    t = st.tabs(tabs)
    with t[0]:
        tab_lectures(c)
    with t[1]:
        tab_badges(c)
    with t[2]:
        tab_grading(c)
    if can_manage:
        with t[3]:
            tab_team(c, role)
        with t[4]:
            tab_settings(c, role)


# ------------------------------------------------------------------------------------------------ lectures
def tab_lectures(c):
    lectures = c["lectures"]
    if not lectures:
        st.info("A course is a series of lectures. Each lecture is a short path of steps: watch, read, answer, hand in.")
    for i, lec in enumerate(lectures):
        n_steps = len(lec["steps"])
        head = f"Lecture {i + 1}: {lec['title']}  ·  {n_steps} step{'s' * (n_steps != 1)}  ·  {lec['status']}"
        with st.expander(head, expanded=S.get("mc_open_lecture") == lec["id"]):
            lecture_editor(c, lec, i, lectures)
    with st.form("new_lecture", clear_on_submit=True):
        cols = st.columns([4, 1])
        t = cols[0].text_input("New lecture", placeholder="Lecture title")
        cols[1].write("")
        if cols[1].form_submit_button("➕ Add lecture", width="stretch") and t.strip():
            r = run("save_lecture", "Lecture added.", course_id=c["id"], title=t.strip())
            if r:
                S["mc_open_lecture"] = r["id"]
                st.rerun()


def lecture_editor(c, lec, i, lectures):
    lid = lec["id"]
    with st.form(f"lec_{lid}"):
        a, b = st.columns([3, 1])
        title = a.text_input("Title", lec["title"])
        status = b.selectbox("Visible to students", ["draft", "published"], index=["draft", "published"].index(lec["status"]),
                             format_func=lambda x: "Yes (published)" if x == "published" else "No (draft)")
        summary = st.text_area("What this lecture is about", lec.get("summary") or "", height=70)
        outcomes = st.text_area("Learning outcomes (one per line)", "\n".join(lec.get("outcomes") or []), height=80)
        if st.form_submit_button("Save lecture"):
            if run("save_lecture", "Lecture saved.", id=lid, title=title.strip(), status=status, summary=summary,
                   outcomes=lines(outcomes)):
                S["mc_open_lecture"] = lid
                st.rerun()
    m = st.columns([1, 1, 4, 1])
    if i > 0 and m[0].button("↑ Move up", key=f"up_{lid}"):
        ids = [x["id"] for x in lectures]
        ids[i - 1], ids[i] = ids[i], ids[i - 1]
        run("reorder", what="lecture", ids=ids) and st.rerun()
    if i < len(lectures) - 1 and m[1].button("↓ Move down", key=f"down_{lid}"):
        ids = [x["id"] for x in lectures]
        ids[i + 1], ids[i] = ids[i], ids[i + 1]
        run("reorder", what="lecture", ids=ids) and st.rerun()
    with m[3].popover("Delete"):
        st.write("Delete this lecture and all its steps? Students' progress on it is lost.")
        if st.button("Yes, delete", key=f"dl_{lid}", type="primary"):
            run("delete", "Lecture deleted.", what="lecture", id=lid) and st.rerun()

    st.markdown("**Steps** — students go through them in this order")
    for j, step in enumerate(lec["steps"]):
        icon, label, _ = STEP_KINDS[step["kind"]]
        q = len(step["questions"])
        with st.container(border=True):
            row = st.columns([6, 1, 1])
            row[0].markdown(f"{icon} **{html.escape(step['title'])}** <span class='mc-muted'>· {label}"
                            f"{f' · {q} question' + 's' * (q != 1) if q else ''}{'' if step['required'] else ' · optional'}</span>",
                            unsafe_allow_html=True)
            editing = S.get("mc_edit_step") == step["id"]
            if row[1].button("Close" if editing else "Edit", key=f"ed_{step['id']}", width="stretch"):
                S["mc_edit_step"] = None if editing else step["id"]
                S["mc_open_lecture"] = lid
                st.rerun()
            if j > 0 and row[2].button("↑", key=f"sup_{step['id']}", width="stretch"):
                ids = [x["id"] for x in lec["steps"]]
                ids[j - 1], ids[j] = ids[j], ids[j - 1]
                S["mc_open_lecture"] = lid
                run("reorder", what="step", ids=ids) and st.rerun()
            if editing:
                step_editor(step, lid)

    st.markdown("<span class='mc-muted'>Add a step:</span>", unsafe_allow_html=True)
    cols = st.columns(len(STEP_KINDS))
    for col, (kind, (icon, label, helptext)) in zip(cols, STEP_KINDS.items()):
        if col.button(f"{icon} {label}", key=f"add_{kind}_{lid}", help=helptext, width="stretch"):
            r = run("save_step", lecture_id=lid, kind=kind, title=f"New {label.lower()}",
                    config={"grading": "manual"} if kind == "assignment" else {})
            if r:
                S["mc_edit_step"], S["mc_open_lecture"] = r["id"], lid
                st.rerun()


def step_editor(step, lid):
    kind, sid, cfg = step["kind"], step["id"], dict(step.get("config") or {})
    with st.form(f"step_{sid}"):
        title = st.text_input("Step title", step["title"])
        if kind == "video":
            link = st.text_input("YouTube link", f"https://youtu.be/{cfg['youtube_id']}" if cfg.get("youtube_id") else "")
            a, b = st.columns(2)
            start = a.text_input("Start at (min:sec, optional)", db.mmss(cfg["start"]) if cfg.get("start") else "")
            end = b.text_input("End at (min:sec, optional)", db.mmss(cfg["end"]) if cfg.get("end") else "")
        elif kind == "pdf":
            st.caption(f"Current file: {cfg['url']}" if cfg.get("url") else "No file yet.")
            pdf = st.file_uploader("Upload a PDF", type=["pdf"], key=f"pdf_{sid}")
        elif kind == "text":
            body = st.text_area("Text (Markdown: **bold**, lists, links)", cfg.get("markdown", ""), height=220)
        elif kind == "assignment":
            instr = st.text_area("Instructions for the student", cfg.get("instructions", ""), height=140)
            grading = st.radio("How is it marked?", ["manual", "auto"], horizontal=True, index=["manual", "auto"].index(cfg.get("grading", "manual")),
                               format_func=lambda x: "A teacher grades it (0–100)" if x == "manual" else "Handing it in is enough")
            allow_file = st.checkbox("Students may attach a file", cfg.get("allow_file", True))
        elif kind == "live":
            link = st.text_input("Meeting link (Jitsi, Zoom, Teams…)", cfg.get("room", ""),
                                 help="Students open this link from the lecture. Joining counts as completing the step.")
            a, b, g = st.columns(3)
            when = a.text_input("Date and time (e.g. 2026-12-01 14:00 CET)", cfg.get("starts_at", ""))
            minutes = b.number_input("Minutes", 15, 480, int(cfg.get("minutes", 60)), step=15)
            group = g.checkbox("Study group (students meet each other)", cfg.get("group", False))
        elif kind == "quiz":
            st.caption("Add the questions below. The quiz is complete when every question is answered correctly; "
                       "its score is the share answered right on the first try.")
        required = st.checkbox("Required to finish the lecture", step["required"])
        save = st.form_submit_button("Save step", type="primary")
    if save:
        try:
            if kind == "video":
                yid = db.youtube_id(link)
                if not yid:
                    raise ValueError("Paste a YouTube link, for example https://youtu.be/abc123XYZ00")
                cfg.update(youtube_id=yid, start=db.parse_mmss(start), end=db.parse_mmss(end))
            elif kind == "pdf" and pdf is not None:
                cfg["url"] = db.upload(pdf.getvalue(), pdf.name, "application/pdf")
                cfg["name"] = pdf.name
            elif kind == "text":
                cfg["markdown"] = body
            elif kind == "assignment":
                cfg.update(instructions=instr, grading=grading, allow_file=allow_file)
            elif kind == "live":
                cfg.update(room=link.strip(), starts_at=when.strip(), minutes=int(minutes), group=group)
        except (ValueError, MoocError) as e:
            st.error(str(e))
            return
        S["mc_open_lecture"] = lid
        run("save_step", "Step saved.", id=sid, title=title.strip() or step["title"], config=cfg, required=required) and st.rerun()

    if kind == "video" and cfg.get("youtube_id"):
        st.video(f"https://www.youtube.com/watch?v={cfg['youtube_id']}", start_time=int(cfg.get("start") or 0))
        st.caption("Play the video to find the moment for a question, then type that time below.")
    if kind == "pdf" and cfg.get("url"):
        st.markdown(f"[Open the PDF]({cfg['url']}) to see the page numbers for questions.")
    if kind in ("video", "pdf", "quiz"):
        questions_editor(step, lid)
    with st.popover("Delete step"):
        st.write("Delete this step and its questions?")
        if st.button("Yes, delete", key=f"ds_{sid}", type="primary"):
            S["mc_open_lecture"], S["mc_edit_step"] = lid, None
            run("delete", "Step deleted.", what="step", id=sid) and st.rerun()


def questions_editor(step, lid):
    kind, sid = step["kind"], step["id"]
    where = {"video": "at (min:sec)", "pdf": "on page"}.get(kind)
    st.markdown("**Questions**" + (" — the video pauses here until the student answers correctly" if kind == "video" else
                                   " — the student must answer before turning past this page" if kind == "pdf" else ""))
    for q in step["questions"]:
        at = db.mmss(q["at_seconds"]) if q.get("at_seconds") is not None else (f"page {q['at_page']}" if q.get("at_page") else "")
        right = ", ".join(q["options"][int(k)] for k in q["correct"] if k.isdigit() and int(k) < len(q["options"]))
        cols = st.columns([1, 6, 1])
        cols[0].markdown(f"<span class='mc-muted'>{at}</span>", unsafe_allow_html=True)
        cols[1].markdown(f"{html.escape(q['prompt'])}  \n<span class='mc-muted'>✔ {html.escape(right)}</span>", unsafe_allow_html=True)
        if cols[2].button("✕", key=f"dq_{q['id']}", help="Delete question"):
            S["mc_open_lecture"], S["mc_edit_step"] = lid, sid
            run("delete", what="question", id=q["id"]) and st.rerun()
    with st.form(f"newq_{sid}", clear_on_submit=True):
        cols = st.columns([1, 3])
        at = cols[0].text_input(f"Show {where}") if where else None
        prompt = cols[1].text_input("Question")
        qkind = st.radio("Type", ["single", "multiple", "truefalse"], horizontal=True,
                         format_func={"single": "One right answer", "multiple": "Several right answers", "truefalse": "True / false"}.get)
        opts = st.text_area("Answers, one per line (ignored for true/false)", height=100)
        right = st.text_input("Number(s) of the right answer(s), e.g. 1 or 1,3 (true/false: 1 = True, 2 = False)")
        expl = st.text_input("Explanation shown after a right answer (optional)")
        must = st.checkbox("Must be answered correctly to go on", True)
        add = st.form_submit_button("➕ Add question")
    if add:
        try:
            options = ["True", "False"] if qkind == "truefalse" else lines(opts)
            if len(options) < 2:
                raise ValueError("Give at least two answers.")
            nums = [int(x) for x in right.replace(" ", "").split(",") if x]
            if not nums or any(n < 1 or n > len(options) for n in nums):
                raise ValueError(f"The right answer must be a number from 1 to {len(options)}.")
            if qkind != "multiple" and len(nums) > 1:
                raise ValueError("This question type has one right answer.")
            extra = {}
            if kind == "video":
                extra["at_seconds"] = db.parse_mmss(at)
                if extra["at_seconds"] is None:
                    raise ValueError("Give the time in the video, e.g. 2:15.")
            elif kind == "pdf":
                if not (at or "").strip().isdigit():
                    raise ValueError("Give the page number.")
                extra["at_page"] = int(at)
            if not prompt.strip():
                raise ValueError("Write the question.")
        except ValueError as e:
            st.error(str(e))
            return
        S["mc_open_lecture"], S["mc_edit_step"] = lid, sid
        run("save_question", step_id=sid, prompt=prompt.strip(), kind=qkind, options=options,
            correct=[str(n - 1) for n in nums], explanation=expl.strip(), must_pass=must, **extra) and st.rerun()


# ------------------------------------------------------------------------------------------------ badges
def tab_badges(c):
    st.caption("Badges are awarded automatically when a student finishes the chosen lectures with at least the minimum "
               "average score (quizzes and graded assignments). The certificate is awarded for the whole course. "
               "Every award gets its own public page that students can share on LinkedIn and other social media.")
    lect = {l["id"]: f"{i + 1}. {l['title']}" for i, l in enumerate(c["lectures"])}
    for b in c["badges"]:
        with st.container(border=True):
            cols = st.columns([1, 5, 1])
            if b.get("image_url"):
                cols[0].image(b["image_url"], width=90)
            else:
                cols[0].markdown("<div style='font-size:46px;text-align:center'>" + ("📜" if b["kind"] == "certificate" else "🏅") + "</div>",
                                 unsafe_allow_html=True)
            rule = ", ".join(lect.get(x, "?") for x in b["lecture_ids"]) if b["lecture_ids"] else "all published lectures"
            cols[1].markdown(f"**{html.escape(b['title'])}** <span class='mc-pill'>{b['kind']}</span>"
                             f"{'' if b['active'] else '<span class=mc-pill>switched off</span>'}  \n"
                             f"<span class='mc-muted'>Finish {html.escape(rule)} with an average of at least {b['min_score']}%. "
                             f"Awarded {b['awarded']} time{'s' * (b['awarded'] != 1)}.</span>", unsafe_allow_html=True)
            with cols[2].popover("Edit"):
                badge_form(c, lect, b)
    with st.expander("➕ New badge or certificate", expanded=not c["badges"]):
        badge_form(c, lect, None)


def badge_form(c, lect, b):
    key = b["id"] if b else "new"
    with st.form(f"badge_{key}", clear_on_submit=b is None):
        kind = st.radio("Type", ["badge", "certificate"], horizontal=True, index=0 if not b or b["kind"] == "badge" else 1,
                        format_func=lambda x: "🏅 Badge (part of the course)" if x == "badge" else "📜 Certificate (whole course)")
        title = st.text_input("Title", b["title"] if b else "")
        desc = st.text_area("What it shows the student can do", (b or {}).get("description") or "", height=70)
        img = st.file_uploader("Design (PNG, JPG, SVG or WebP; square works best for badges)", type=["png", "jpg", "jpeg", "svg", "webp"],
                               key=f"img_{key}")
        lects = st.multiselect("Lectures to finish (leave empty for all)", list(lect), default=(b or {}).get("lecture_ids") or [],
                               format_func=lambda x: lect[x])
        score = st.slider("Minimum average score (%)", 0, 100, (b or {}).get("min_score", c.get("pass_score", 70)), 5)
        active = st.checkbox("Award it", (b or {}).get("active", True)) if b else True
        go = st.form_submit_button("Save", type="primary")
    if go:
        if len(title.strip()) < 2:
            st.error("Give it a title.")
            return
        image_url = (b or {}).get("image_url")
        if img is not None:
            types = {"png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "svg": "image/svg+xml", "webp": "image/webp"}
            try:
                image_url = db.upload(img.getvalue(), img.name, types[img.name.rsplit(".", 1)[-1].lower()])
            except MoocError as e:
                st.error(str(e))
                return
        args = dict(kind=kind, title=title.strip(), description=desc.strip(), image_url=image_url, lecture_ids=lects,
                    min_score=score, active=active)
        if b:
            args["id"] = b["id"]
        else:
            args["course_id"] = c["id"]
        run("save_badge", "Saved.", **args) and st.rerun()
    if b:
        if st.button("Delete", key=f"delb_{key}", help="If it was already awarded, it is switched off instead; issued awards stay valid."):
            run("delete", "Deleted.", what="badge", id=b["id"]) and st.rerun()


# ------------------------------------------------------------------------------------------------ grading
def tab_grading(c):
    subs = load("submissions", course_id=c["id"])["submissions"]
    st.markdown(f"#### To grade ({len(subs)})")
    if not subs:
        st.caption("Nothing waiting. Handed-in assignments that need a mark appear here.")
    for s in subs:
        who = s["student"]
        with st.container(border=True):
            st.markdown(f"**{html.escape(display_name(who))}** <span class='mc-muted'>({html.escape(who['username'])}) · "
                        f"{html.escape(s['lecture_title'])} → {html.escape(s['step_title'])} · {s['submitted_at'][:16].replace('T', ' ')}</span>",
                        unsafe_allow_html=True)
            if s.get("answer"):
                st.markdown(s["answer"])
            if s.get("file_url"):
                st.markdown(f"📎 [Attached file]({s['file_url']})")
            with st.form(f"grade_{s['id']}"):
                a, b = st.columns([1, 3])
                score = a.number_input("Score (0–100)", 0, 100, 80, 5)
                fb = b.text_input("Feedback to the student")
                if st.form_submit_button("Save grade", type="primary"):
                    r = run("grade", submission_id=s["id"], score=score, feedback=fb.strip())
                    if r:
                        got = r.get("awarded") or []
                        flash("success", "Graded." + (f" The student earned: {', '.join(a['title'] for a in got)} 🎉" if got else ""))
                        st.rerun()
    st.markdown("#### Students")
    st_data = load("students", course_id=c["id"])
    rows = st_data["students"]
    if not rows:
        st.caption("No students yet. They enrol on the MOOC website once the course is published.")
        return
    total = max(st_data["steps"], 1)
    df = pd.DataFrame([{"Name": display_name(r), "Username": r["username"], "Progress": min(r["done"] / total, 1.0),
                        "Average score": r["score"], "Awards": ", ".join(r["awards"]),
                        "Last active": (r.get("last_active") or "")[:10], "Enrolled": r["enrolled"][:10]} for r in rows])
    st.dataframe(df, hide_index=True, width="stretch",
                 column_config={"Progress": st.column_config.ProgressColumn(format="percent", min_value=0, max_value=1)})


# ------------------------------------------------------------------------------------------------ team
def tab_team(c, role):
    st.caption("Give Octa accounts a role in this course. Teachers build lectures and grade; the course admin also "
               "manages the team and the course settings. Students usually enrol themselves on the website.")
    names = {"admin": "Course admin", "teacher": "Teacher", "student": "Student"}
    for m in c["members"]:
        cols = st.columns([3, 2, 2, 1])
        cols[0].markdown(f"**{html.escape(display_name(m))}** <span class='mc-muted'>{html.escape(m['username'])}</span>", unsafe_allow_html=True)
        cols[1].markdown(names[m["role"]])
        cols[2].markdown(f"<span class='mc-muted'>{html.escape(m.get('email') or '')}</span>", unsafe_allow_html=True)
        if (m["role"] != "admin" or role == "super") and cols[3].button("Remove", key=f"rm_{m['id']}"):
            run("set_member", "Removed from the course.", course_id=c["id"], user_id=m["id"], remove=True) and st.rerun()
    with st.form("add_member", clear_on_submit=True):
        a, b, cc = st.columns([3, 2, 1])
        who = a.text_input("Username or email of an Octa account")
        roles = ["teacher", "student"] + (["admin"] if role == "super" else [])
        r = b.selectbox("Role", roles, format_func=names.get)
        cc.write("")
        if cc.form_submit_button("Add", width="stretch") and who.strip():
            run("set_member", "Added.", course_id=c["id"], user=who.strip(), role=r) and st.rerun()
    st.caption("Someone without an Octa account registers first (on the MOOC website or the Octa suite).")


# ------------------------------------------------------------------------------------------------ settings
def tab_settings(c, role):
    with st.form("course_settings"):
        title = st.text_input("Title", c["title"])
        a, b = st.columns(2)
        slug = a.text_input("Web address name", c["slug"], help="The course page will be mooc.cloudearthi.com/course/<this>")
        status = b.selectbox("Status", ["draft", "published", "archived"], index=["draft", "published", "archived"].index(c["status"]),
                             format_func={"draft": "Draft (hidden)", "published": "Published (open to students)",
                                          "archived": "Archived (hidden, students keep awards)"}.get)
        proj = None
        if role == "super":
            ids = [""] + list(project_names)
            proj = st.selectbox("Project", ids, index=ids.index(c.get("project_id") or "") if (c.get("project_id") or "") in ids else 0,
                                format_func=lambda x: project_names.get(x, "— no project —"))
        summary = st.text_input("One-line summary", c.get("summary") or "")
        desc = st.text_area("Description", c.get("description") or "", height=140)
        outcomes = st.text_area("Learning outcomes of the course (one per line)", "\n".join(c.get("outcomes") or []), height=100)
        a, b, d, e = st.columns(4)
        level = a.selectbox("Level", LEVELS, index=LEVELS.index(c.get("level") or ""), format_func=lambda x: x or "—")
        lang = b.text_input("Language", c.get("language") or "English")
        hours = d.number_input("Study hours", 0.0, 999.0, float(c.get("hours") or 0), 0.5)
        pass_score = e.number_input("Pass score (%)", 0, 100, int(c.get("pass_score") or 70), 5,
                                    help="The default minimum score for new badges and certificates.")
        cover = st.file_uploader("Cover image", type=["png", "jpg", "jpeg", "webp"])
        if c.get("image_url"):
            st.image(c["image_url"], width=240)
        go = st.form_submit_button("Save course", type="primary")
    if go:
        if status == "published" and not any(l["status"] == "published" for l in c["lectures"]):
            st.error("Publish at least one lecture before publishing the course.")
            return
        image_url = c.get("image_url")
        if cover is not None:
            try:
                image_url = db.upload(cover.getvalue(), cover.name, "image/png" if cover.name.lower().endswith("png") else
                                      "image/webp" if cover.name.lower().endswith("webp") else "image/jpeg")
            except MoocError as e:
                st.error(str(e))
                return
        args = dict(id=c["id"], title=title.strip(), slug=db.slugify(slug), status=status, summary=summary.strip(),
                    description=desc, outcomes=lines(outcomes), level=level, language=lang.strip(),
                    hours=str(hours) if hours else "", pass_score=int(pass_score), image_url=image_url)
        if role == "super":
            args["project_id"] = proj
        run("save_course", "Course saved.", **args) and st.rerun()
    if role == "super":
        with st.popover("Delete course"):
            st.write("Delete this course with all its lectures and badges? Courses with students can only be archived.")
            if st.button("Yes, delete the course", type="primary"):
                if run("delete_course", "Course deleted.", id=c["id"]):
                    S.pop("mc_course", None)
                    st.rerun()


# ================================================================================================ projects
def page_projects():
    st.markdown("## Projects")
    st.caption("A project groups courses on the MOOC website, e.g. BOOSTalent, SEEDplus or Inspiring the Minds.")
    show_flash()
    counts = {}
    for c in overview["courses"]:
        counts[c.get("project_id")] = counts.get(c.get("project_id"), 0) + 1
    for p in projects + [None]:
        label = f"{p['title']}  ·  {counts.get(p['id'], 0)} courses" if p else "➕ New project"
        with st.expander(label, expanded=p is None and not projects):
            with st.form(f"proj_{p['id'] if p else 'new'}", clear_on_submit=p is None):
                title = st.text_input("Name", (p or {}).get("title", ""))
                desc = st.text_area("Description", (p or {}).get("description") or "", height=90)
                a, b = st.columns(2)
                site = a.text_input("Project website", (p or {}).get("website") or "")
                order = b.number_input("Order on the website", 0, 999, int((p or {}).get("sort_order", 100)), 10)
                logo = st.file_uploader("Logo or image", type=["png", "jpg", "jpeg", "webp", "svg"], key=f"pl_{(p or {}).get('id', 'new')}")
                go = st.form_submit_button("Save", type="primary")
            if go:
                if len(title.strip()) < 2:
                    st.error("Give the project a name.")
                    continue
                image_url = (p or {}).get("image_url")
                if logo is not None:
                    ext = logo.name.rsplit(".", 1)[-1].lower()
                    try:
                        image_url = db.upload(logo.getvalue(), logo.name, {"svg": "image/svg+xml", "png": "image/png", "webp": "image/webp"}.get(ext, "image/jpeg"))
                    except MoocError as e:
                        st.error(str(e))
                        continue
                args = dict(title=title.strip(), description=desc, website=site.strip(), sort_order=int(order), image_url=image_url)
                if p:
                    args["id"] = p["id"]
                run("save_project", "Project saved.", **args) and st.rerun()
            if p:
                with st.popover("Delete project"):
                    st.write("Delete this project? Its courses stay, without a project.")
                    if st.button("Yes, delete", key=f"dp_{p['id']}", type="primary"):
                        run("delete_project", "Project deleted.", id=p["id"]) and st.rerun()


# ================================================================================================ people
def page_people():
    st.markdown("## People")
    show_flash()
    people = load("people")["people"]
    pending = [p for p in people if p["kind"] == "teacher" and p["status"] == "pending"]
    st.markdown(f"#### Teachers waiting for approval ({len(pending)})")
    if not pending:
        st.caption("Nobody is waiting.")
    for p in pending:
        cols = st.columns([4, 3, 1, 1])
        cols[0].markdown(f"**{html.escape(display_name(p))}** <span class='mc-muted'>{html.escape(p['username'])}</span>", unsafe_allow_html=True)
        cols[1].markdown(f"<span class='mc-muted'>{html.escape(p.get('affiliation') or '')} · {html.escape(p['email'])}</span>", unsafe_allow_html=True)
        if cols[2].button("Approve", key=f"ap_{p['id']}", type="primary"):
            run("decide_teacher", "Approved. Add them to a course in its Team tab.", user_id=p["id"], approve=True) and st.rerun()
        if cols[3].button("Decline", key=f"de_{p['id']}"):
            run("decide_teacher", "Declined.", user_id=p["id"], approve=False) and st.rerun()
    st.markdown("#### Everyone on the MOOC")
    if people:
        st.dataframe(pd.DataFrame([{"Name": display_name(p), "Username": p["username"], "Email": p["email"],
                                    "Affiliation": p.get("affiliation") or "", "Registered as": p["kind"],
                                    "Status": p["status"], "Courses": p["courses"], "Since": p["created_at"][:10]} for p in people]),
                     hide_index=True, width="stretch")
    if is_super:
        st.markdown("#### Super admins")
        sup = load("super_admins")["super_admins"]
        for s in sup:
            cols = st.columns([4, 3, 1])
            cols[0].markdown(f"**{html.escape(display_name(s))}** <span class='mc-muted'>{html.escape(s['username'])}</span>", unsafe_allow_html=True)
            cols[1].markdown("<span class='mc-muted'>Octa admin</span>" if s["octa_admin"] else "", unsafe_allow_html=True)
            if not s["octa_admin"] and s["id"] != user["id"] and cols[2].button("Remove", key=f"rs_{s['id']}"):
                run("set_super", "Removed.", user_id=s["id"], on=False) and st.rerun()
        with st.form("add_super", clear_on_submit=True):
            a, b = st.columns([4, 1])
            who = a.text_input("Make a super admin (username or email)")
            b.write("")
            if b.form_submit_button("Add", width="stretch") and who.strip():
                run("set_super", "Super admin added.", user=who.strip(), on=True) and st.rerun()


# ================================================================================================ route
if page == "Courses" and S.get("mc_course"):
    page_course(S["mc_course"])
elif page == "Courses":
    page_courses()
elif page == "Projects":
    page_projects()
else:
    page_people()
