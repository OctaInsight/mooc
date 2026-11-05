"""Runs the Studio app against FakeMooc, signed in, without a database (used by test_studio.py)."""
import os
import runpy
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
for p in (ROOT, HERE):
    if p not in sys.path:
        sys.path.insert(0, p)

import octa_auth  # noqa: E402
import mooc_db  # noqa: E402
import fake_mooc  # noqa: E402

if not hasattr(fake_mooc, "CURRENT"):
    fake_mooc.CURRENT = fake_mooc.FakeMooc(os.environ.get("FAKE_ROLE", "super"))
FAKE = fake_mooc.CURRENT
USER = dict(id="u-me", username="me", first_name="Tamer", last_name="A", email="me@x.org", role="admin", apps=["octa_mooc"])


def _manage(action, **args):
    r = FAKE(action, **args)
    if not r.get("ok"):
        raise mooc_db.MoocError(r.get("error"))
    return r


octa_auth.require_login = lambda app, required=True: USER
octa_auth.sidebar = lambda app: None
mooc_db.manage = _manage
mooc_db.upload = lambda data, name, ctype: f"https://example.org/{name}"
runpy.run_path(os.path.join(ROOT, "app.py"), run_name="__main__")
