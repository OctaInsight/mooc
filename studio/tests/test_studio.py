"""Walks through the Studio pages as a super admin and as a teacher (python -m pytest tests)."""
import os
import sys

from streamlit.testing.v1 import AppTest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import fake_mooc  # noqa: E402

SCRIPT = os.path.join(HERE, "fake_studio.py")


def fresh(role="super"):
    fake_mooc.CURRENT = fake_mooc.FakeMooc(role)
    at = AppTest.from_file(SCRIPT, default_timeout=30)
    at.run()
    assert not at.exception, at.exception
    return at, fake_mooc.CURRENT


def btn(at, label):
    return next(b for b in at.button if b.label == label)


def errors(at):
    return [e.value for e in at.error]


def test_super_admin_builds_a_course():
    at, fake = fresh()
    assert "Hello" in at.markdown[1].value or any("Hello" in m.value for m in at.markdown)
    # project
    at.sidebar.radio[0].set_value("Projects").run()
    at.text_input(key=None) if False else None
    form_inputs = [t for t in at.text_input if t.label == "Name"]
    form_inputs[-1].input("BOOSTalent")
    at.button[-1] if False else None
    next(b for b in at.button if b.label == "Save").click().run()
    assert not at.exception and not errors(at), errors(at)
    assert [p["title"] for p in fake.projects.values()] == ["BOOSTalent"]
    # course
    at.sidebar.radio[0].set_value("Courses").run()
    next(t for t in at.text_input if t.label == "Course title").input("Innovation 101")
    btn(at, "Create course").click().run()
    assert not at.exception and not errors(at), errors(at)
    cid = next(iter(fake.courses))
    assert at.session_state["mc_course"] == cid
    # lecture + video step + question
    next(t for t in at.text_input if t.label == "New lecture").input("What is innovation?")
    btn(at, "➕ Add lecture").click().run()
    assert not at.exception and len(fake.lectures) == 1
    btn(at, "🎬 Video").click().run()
    assert not at.exception, at.exception
    sid = next(iter(fake.steps))
    next(t for t in at.text_input if t.label == "YouTube link").input("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=3")
    btn(at, "Save step").click().run()
    assert not errors(at), errors(at)
    assert fake.steps[sid]["config"]["youtube_id"] == "dQw4w9WgXcQ"
    def fill(time, question, answers, right):
        n = at.session_state[f"mc_qform_{sid}"] if f"mc_qform_{sid}" in at.session_state else 0
        next(t for t in at.text_input if t.label == "Show at (min:sec)").input(time)
        next(t for t in at.text_input if t.label == "Question").input(question)
        for i, a in enumerate(answers):
            at.text_input(key=f"q_{sid}_{n}_a{i}").input(a)
        for i in right:
            at.checkbox(key=f"q_{sid}_{n}_r{i}").check()
        btn(at, "Save question").click().run()
        assert not at.exception, at.exception

    # forgetting to tick the right answer is refused, and what was typed stays in the form
    fill("1:30", "What adds value?", ["New ideas", "Old habits"], [])
    assert any("Tick the right answer" in e for e in errors(at)), errors(at)
    assert not fake.questions
    assert next(t for t in at.text_input if t.label == "Question").value == "What adds value?"
    # a correct question is saved, with a confirmation, and the form is empty again
    at.checkbox(key=f"q_{sid}_0_r0").check()
    btn(at, "Save question").click().run()
    assert not errors(at), errors(at)
    q = next(iter(fake.questions.values()))
    assert q["at_seconds"] == 90 and q["correct"] == ["0"] and q["options"] == ["New ideas", "Old habits"]
    assert any("Question added at 1:30" in m.value for m in at.success), [m.value for m in at.success]
    assert next(t for t in at.text_input if t.label == "Question").value == ""
    # several answers ticked on a one-answer question is refused
    fill("2.05", "Pick one", ["a", "b", "c"], [0, 2])
    assert any("only one right answer" in e for e in errors(at)), errors(at)
    assert len(fake.questions) == 1
    # badge
    next(t for t in at.text_input if t.label == "Title" and t.value == "").input("Innovation basics")
    saves = [b for b in at.button if b.label == "Save"]
    saves[-1].click().run()
    assert not errors(at), errors(at)
    assert [b["title"] for b in fake.badges.values()] == ["Innovation basics"]
    # team: add a teacher
    next(t for t in at.text_input if t.label.startswith("Username or email")).input("teach")
    btn(at, "Add").click().run()
    assert fake.members[(cid, "u-t")] == "teacher"
    # people page: approve the waiting teacher
    at.sidebar.radio[0].set_value(at.sidebar.radio[0].options[2]).run()
    assert not at.exception
    btn(at, "Approve").click().run()
    assert fake.people["u-t"]["status"] == "active"


def test_teacher_sees_no_admin_pages():
    at, fake = fresh("teacher")
    assert at.sidebar.radio[0].options == ["Courses"]
    assert not any(b.label == "Create course" for b in at.button)


def test_newcomer_asks_to_teach_and_a_super_admin_approves():
    fake_mooc.CURRENT = fake = fake_mooc.FakeMooc("none")
    fake("save_course", title="AI course", status="published")
    cid = next(iter(fake.courses))
    at = AppTest.from_file(SCRIPT, default_timeout=30)
    at.run()
    assert not at.exception, at.exception
    assert at.radio[0].label == "I want to join as" and len(at.radio[0].options) == 3
    at.radio[0].set_value("teacher")
    at.text_area[0].input("I teach AI at a university")
    btn(at, "Send").click().run()
    assert not at.exception, at.exception
    r = next(iter(fake.reqs.values()))
    assert r["role"] == "teacher" and r["course_id"] == cid and r["message"] == "I teach AI at a university"
    assert any("request to be teacher" in m.value for m in at.success), [m.value for m in at.success]
    assert any("Waiting for approval" in m.value for m in at.info)
    # a student enrols at once
    at.radio[0].set_value("student")
    btn(at, "Send").click().run()
    assert fake.members[(cid, "u-me")] == "student"
    assert any("You are enrolled" in m.value for m in at.success)
    # a super admin sees the request on the People page and approves it
    fake.role = "super"
    fake.users["u-t"]["id"] = "u-t"
    r["user_id"] = "u-t"
    at2 = AppTest.from_file(SCRIPT, default_timeout=30)
    at2.run()
    assert "People (1 waiting)" in at2.sidebar.radio[0].options
    at2.sidebar.radio[0].set_value("People (1 waiting)").run()
    assert not at2.exception, at2.exception
    assert any("wants to be **teacher** of **AI course**" in m.value for m in at2.markdown)
    btn(at2, "Approve").click().run()
    assert fake.members[(cid, "u-t")] == "teacher" and r["status"] == "approved"
