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
        self.reqs = {}
        self.awards = {}
        self.sent, self.mail_limit = [], None
        self.outbox, self.claimed, self.mail_done, self.resets = [], [], [], []   # emails "sent" by the stubbed mail.send; stop after mail_limit

    def rpc(self, name, **a):
        """The student-side functions MOOC Studio calls directly (mooc_join_options, mooc_register)."""
        if name == "mooc_mail_claim_app":                    # the award outbox (server key checked by the database)
            people, self.outbox = self.outbox, []
            self.claimed += [a["id"] for p in people for a in p["awards"]]
            return dict(ok=True, people=people)
        if name == "mooc_mail_done_app":
            self.mail_done.append(dict(ids=a["p_ids"], ok=a["p_ok"], error=a.get("p_error"), count=a.get("p_count", True)))
            return dict(ok=True)
        if name == "mooc_mail_status":
            return dict(ok=True, pending=len(self.outbox), failed=0, last_error=None)
        if name == "mooc_site_reset_app":
            self.resets.append(a["p_email"])
            if a["p_email"] == "kim@example.org":
                return dict(ok=True, exists=True, token="t" * 64, username="kim", name="Kim K", email="kim@example.org")
            return dict(ok=True, exists=False)
        if name == "mooc_join_options":
            return dict(ok=True, person=None, requests=[dict(r, course=self.courses[r["course_id"]]["title"]) for r in self.reqs.values()],
                        courses=[dict(id=c["id"], slug=c["slug"], title=c["title"], status=c["status"], project=None,
                                      my_role=self.members.get((c["id"], "u-me"))) for c in self.courses.values()])
        if name == "mooc_register":
            c = self.courses[a["p_course"]]
            if a["p_kind"] == "student":
                if c["status"] != "published":
                    return dict(ok=False, error="This course is not open to students yet.")
                self.members[(c["id"], "u-me")] = "student"
                return dict(ok=True, status="enrolled", slug=c["slug"])
            rid = self._id()
            self.reqs[rid] = dict(id=rid, user_id="u-me", course_id=c["id"], role=a["p_kind"], status="pending",
                                  message=a.get("p_message"), created_at=_now())
            return dict(ok=True, status="requested", request_id=rid)
        return dict(ok=False, error="unknown " + name)

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
                        pending_teachers=sum(1 for x in self.people.values() if x["status"] == "pending"),
                        pending_requests=sum(1 for r in self.reqs.values() if r["status"] == "pending"))
        if action == "course":
            return dict(ok=True, my_role="super" if sup else self.role, course=self.course_full(p["course_id"]))
        if action == "requests":
            return dict(ok=True, requests=[dict(self.users[r["user_id"]], request_id=r["id"], course_id=r["course_id"],
                                                course=self.courses[r["course_id"]]["title"], role=r["role"],
                                                message=r.get("message"), created_at=r["created_at"])
                                           for r in self.reqs.values() if r["status"] == "pending"])
        if action == "decide_request":
            r = self.reqs[p["request_id"]]
            if r["role"] == "admin" and not sup:
                return dict(ok=False, error="Only a super admin approves course admins.")
            r["status"] = "approved" if p["approve"] else "declined"
            if p["approve"]:
                self.members[(r["course_id"], r["user_id"])] = r["role"]
            return dict(ok=True)
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
            base = self.badges.get(bid) or dict(id=bid, course_id=p.get("course_id"), active=True, lecture_ids=[], min_score=70, kind="badge")
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
        if action == "bulk_award":
            if self.role not in ("super", "admin"):
                return dict(ok=False, error="Only a course admin or super admin issues certificates.")
            out, seen = [], set()
            for r in p["rows"]:
                email = (r.get("email") or "").strip().lower()
                if not r.get("name") or "@" not in email or email in seen:
                    continue
                seen.add(email)
                for bid in p["badge_ids"]:
                    b = self.badges[bid]
                    old = next((a for a in self.awards.values() if a["badge_id"] == bid and a["email"] == email), None)
                    if old:
                        out.append(dict(old, new=False))
                        continue
                    aid = self._id()
                    a = dict(award_id=aid, badge_id=bid, course_id=b["course_id"], title=b["title"], kind=b["kind"],
                             name=r["name"], email=email, contribution=r.get("contribution") or p.get("default_contribution") or None,
                             issued_at=p.get("issued_at") or _now(), source="bulk", email_sent_at=None, email_error=None,
                             revoked=False, has_account=False)
                    self.awards[aid] = a
                    out.append(dict(a, new=True))
            return dict(ok=True, awards=out)
        if action == "invite_students":
            if self.role not in ("super", "admin"):
                return dict(ok=False, error="Only the course admin or a super admin can add people to this course.")
            out = []
            for r in p["rows"]:
                email = r["email"].lower()
                u = next((k for k, v in self.users.items() if v["email"] == email), None)
                created = u is None
                if created:
                    u = "u-" + email
                    self.users[u] = dict(id=u, username=email.split("@")[0], first_name=r.get("first_name") or r["name"],
                                         last_name=r.get("last_name") or "", email=email, affiliation="", invited=True)
                self.members.setdefault((p["course_id"], u), "student")
                token = self._id().replace("-", "") if self.users[u].get("invited") else None
                out.append(dict(email=email, username=self.users[u]["username"], created=created, set_password_token=token))
            return dict(ok=True, people=out)
        if action == "awards":
            return dict(ok=True, awards=[a for a in self.awards.values() if a["course_id"] == p["course_id"]])
        if action == "award_email":
            for i in p["ids"]:
                a = self.awards[i]
                a["email_sent_at"], a["email_error"] = (_now(), None) if p["sent"] else (None, p.get("error"))
            return dict(ok=True)
        if action == "revoke_award":
            self.awards[p["id"]]["revoked"] = p.get("revoked", True)
            return dict(ok=True)
        if action in ("delete_project", "delete_course", "set_super", "upload_ticket"):
            return dict(ok=True, ticket="t")
        return dict(ok=False, error="Unknown action.")
