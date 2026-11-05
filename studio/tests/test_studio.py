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
    next(t for t in at.text_input if t.label == "Show at (min:sec)").input("1:30")
    next(t for t in at.text_input if t.label == "Question").input("What adds value?")
    next(t for t in at.text_area if t.label.startswith("Answers")).input("New ideas\nOld habits")
    next(t for t in at.text_input if t.label.startswith("Number(s)")).input("1")
    btn(at, "➕ Add question").click().run()
    assert not errors(at), errors(at)
    q = next(iter(fake.questions.values()))
    assert q["at_seconds"] == 90 and q["correct"] == ["0"] and q["options"] == ["New ideas", "Old habits"]
    # a bad question is refused with a message
    next(t for t in at.text_input if t.label == "Show at (min:sec)").input("1:30")
    next(t for t in at.text_input if t.label == "Question").input("Bad")
    next(t for t in at.text_area if t.label.startswith("Answers")).input("a\nb")
    next(t for t in at.text_input if t.label.startswith("Number(s)")).input("5")
    btn(at, "➕ Add question").click().run()
    assert any("from 1 to 2" in e for e in errors(at))
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


def test_stranger_can_ask_to_teach():
    at, fake = fresh("none")
    assert any("Ask to become a teacher" == b.label for b in at.button)
