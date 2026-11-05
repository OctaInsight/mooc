"""In-memory stand-in for the mooc_manage database function, for testing the Studio pages without a database.
It follows the same actions and answers; permission checks are simplified (the real ones are tested in SQL)."""
import uuid
from datetime import datetime, timezone


def _now():
    return datetime.now(timezone.utc).isoformat()


class FakeMooc:
    def __init__(self, role="super"):
        self.role = role          # role of the signed-in user: super | admin | teacher | none
        self.uid = "u-me"
        self.users = {"u-me": dict(id="u-me", username="me", first_name="Tamer", last_name="A", email="me@x.org", affiliation="Octa"),
                      "u-t": dict(id="u-t", username="teach", first_name="Tea", last_name="Cher", email="t@x.org", affiliation="Uni")}
        self.people = {"u-t": dict(kind="teacher", status="pending", created_at=_now())}
        self.projects, self.courses, self.members, self.lectures, self.steps, self.questions = {}, {}, {}, {}, {}, {}
        self.badges, self.subs = {}, {}

    def _id(self):
        return str(uuid.uuid4())

    def course_full(self, cid):
        c = dict(self.courses[cid])
        lec = sorted([l for l in self.lectures.values() if l["course_id"] == cid], key=lambda l: l["position"])
        c["lectures"] = []
        for l in lec:
            l = dict(l)
            st = sorted([s for s in self.steps.values() if s["lecture_id"] == l["id"]], key=lambda s: s["position"])
            l["steps"] = [dict(s, questions=[q for q in self.questions.values() if q["step_id"] == s["id"]]) for s in st]
            c["lectures"].append(l)
        c["badges"] = [dict(b, awarded=0) for b in self.badges.values() if b["course_id"] == cid]
        c["members"] = [dict(self.users[u], role=r, status="active") for (cc, u), r in self.members.items() if cc == cid]
        c["project"] = self.projects.get(c.get("project_id"))
        return c

    def __call__(self, action, **p):
        sup = self.role == "super"
        if action == "me":
            return dict(ok=True, is_super=sup, person=None, is_course_admin=self.role == "admin",
                        can_edit_any=self.role in ("super", "admin", "teacher"))
        if action == "overview":
            cs = [dict(c, my_role="super" if sup else self.role, lectures=0, students=0, awards=0, to_grade=len(self.subs))
                  for c in self.courses.values()]
            return dict(ok=True, projects=list(self.projects.values()), courses=cs,
                        pending_teachers=sum(1 for x in self.people.values() if x["status"] == "pending"))
        if action == "course":
            return dict(ok=True, my_role="super" if sup else self.role, course=self.course_full(p["course_id"]))
        if action == "people":
            return dict(ok=True, people=[dict(self.users[u], **x, courses=0) for u, x in self.people.items()])
        if action == "super_admins":
            return dict(ok=True, super_admins=[dict(self.users["u-me"], octa_admin=True)])
        if action == "submissions":
            return dict(ok=True, submissions=list(self.subs.values()))
        if action == "students":
            return dict(ok=True, steps=3, students=[dict(self.users["u-t"], enrolled=_now(), done=2, score=75.0,
                                                         awards=["Basics"], last_active=_now())])
        if action == "save_project":
            pid = p.get("id") or self._id()
            self.projects[pid] = {**dict(sort_order=100), **self.projects.get(pid, {}), **p, "id": pid}
            return dict(ok=True, id=pid)
        if action == "save_course":
            cid = p.get("id") or self._id()
            base = self.courses.get(cid) or dict(id=cid, slug="c-" + cid[:4], status="draft", outcomes=[], pass_score=70,
                                                 language="English", created_at=_now())
            base.update({k: v for k, v in p.items() if k != "id"})
            self.courses[cid] = base
            return dict(ok=True, id=cid)
        if action == "save_lecture":
            lid = p.get("id") or self._id()
            base = self.lectures.get(lid) or dict(id=lid, course_id=p.get("course_id"), position=10 * (len(self.lectures) + 1),
                                                  status="draft", outcomes=[], summary="")
            base.update({k: v for k, v in p.items() if k not in ("id", "course_id")})
            self.lectures[lid] = base
            return dict(ok=True, id=lid)
        if action == "save_step":
            sid = p.get("id") or self._id()
            base = self.steps.get(sid) or dict(id=sid, lecture_id=p["lecture_id"], position=10 * (len(self.steps) + 1),
                                               kind=p["kind"], required=True, config={})
            base.update({k: v for k, v in p.items() if k not in ("id", "lecture_id", "kind")})
            self.steps[sid] = base
            return dict(ok=True, id=sid)
        if action == "save_question":
            if not p.get("correct"):
                return dict(ok=False, error="Mark at least one correct answer.")
            qid = self._id()
            self.questions[qid] = {"at_seconds": None, "at_page": None, **p, "id": qid}
            return dict(ok=True, id=qid)
        if action == "save_badge":
            bid = p.get("id") or self._id()
            base = self.badges.get(bid) or dict(id=bid, course_id=p.get("course_id"), active=True, lecture_ids=[])
            base.update({k: v for k, v in p.items() if k not in ("id",)})
            self.badges[bid] = base
            return dict(ok=True, id=bid)
        if action == "set_member":
            if p.get("role") == "admin" and not sup:
                return dict(ok=False, error="Only a super admin names or changes course admins.")
            u = p.get("user_id") or next((k for k, v in self.users.items() if v["username"] == p.get("user")), None)
            if not u:
                return dict(ok=False, error="No Octa account with that username or email.")
            if p.get("remove"):
                self.members.pop((p["course_id"], u), None)
            else:
                self.members[(p["course_id"], u)] = p["role"]
            return dict(ok=True)
        if action == "delete":
            store = {"lecture": self.lectures, "step": self.steps, "question": self.questions, "badge": self.badges}[p["what"]]
            store.pop(p["id"], None)
            return dict(ok=True)
        if action == "reorder":
            store = self.lectures if p["what"] == "lecture" else self.steps
            for n, i in enumerate(p["ids"]):
                store[i]["position"] = (n + 1) * 10
            return dict(ok=True)
        if action == "grade":
            self.subs.pop(p["submission_id"], None)
            return dict(ok=True, awarded=[{"title": "Certificate"}])
        if action == "decide_teacher":
            self.people[p["user_id"]]["status"] = "active" if p["approve"] else "declined"
            return dict(ok=True)
        if action in ("delete_project", "delete_course", "set_super", "upload_ticket"):
            return dict(ok=True, ticket="t")
        return dict(ok=False, error="Unknown action.")
