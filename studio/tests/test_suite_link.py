"""The Octa suite button must open the suite, even when the secrets point portal_url at this app."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from octa_auth import App, ui  # noqa: E402

MOOC = App(id="octa_mooc", name="MOOC Studio", url="https://cloudearthi-mooc.streamlit.app/")


def test_suite_link(monkeypatch):
    for setting, expected in [("https://cloudearthi-mooc.streamlit.app", ui.SUITE_URL),   # pointed at itself
                              ("HTTPS://cloudearthi-mooc.streamlit.app/?x=1", ui.SUITE_URL),
                              ("", ui.SUITE_URL),                                          # not set
                              ("https://octa-suite.streamlit.app/", "https://octa-suite.streamlit.app/"),
                              ("https://portal.example.org/", "https://portal.example.org/")]:
        monkeypatch.setattr(ui.client, "setting", lambda name, default=None, v=setting: v or default)
        assert ui.suite_link(MOOC) == expected, setting
