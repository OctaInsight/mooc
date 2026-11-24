"""Turn Academy LMS lesson HTML into the small Markdown the new MOOC shows (bold, italic, links, "- " lists, paragraphs)."""
import re
from html import unescape
from html.parser import HTMLParser

URL = re.compile(r"(?<!\()(https?://[^\s<)\]]+)")


class _Md(HTMLParser):
    def __init__(self):
        super().__init__()
        self.blocks, self.cur, self.lists, self.item = [], [], [], None   # lists: stack of [kind, counter]

    def _text(self, s):
        (self.item if self.item is not None else self.cur).append(s)

    def handle_starttag(self, tag, attrs):
        if tag in ("strong", "b"):
            self._text("**")
        elif tag in ("em", "i"):
            self._text("*")
        elif tag == "br":
            self._text("\n")
        elif tag in ("ul", "ol"):
            self._flush()
            self.lists.append([tag, 0])
            self.blocks.append([])                           # a list is one block of lines
        elif tag == "li":
            self.item = []
        elif tag == "a":
            self._href = dict(attrs).get("href")
            self._text("[")

    def handle_endtag(self, tag):
        if tag in ("strong", "b"):
            self._text("**")
        elif tag in ("em", "i"):
            self._text("*")
        elif tag == "p":
            self._flush()
        elif tag == "li" and self.item is not None and self.lists:
            kind = self.lists[-1]
            kind[1] += 1
            text = _tidy("".join(self.item))
            if text:
                self.blocks[-1].append(("- " if kind[0] == "ul" else f"{kind[1]}. ") + text)
            self.item = None
        elif tag in ("ul", "ol") and self.lists:
            self.lists.pop()
        elif tag == "a":
            self._text(f"]({self._href})" if getattr(self, "_href", None) else "]")

    def handle_data(self, data):
        self._text(data.replace("\n", " "))

    def _flush(self):
        text = _tidy("".join(self.cur))
        if text:
            self.blocks.append([text])
        self.cur = []

    def result(self):
        self._flush()
        return "\n\n".join("\n".join(b) for b in self.blocks if b)


def _tidy(s):
    s = unescape(s)
    s = re.sub(r"\*\*\*(.+?)\*\*\*", r"**\1**", s)            # bold + italic: keep bold
    s = re.sub(r"\*\*\s*\*\*", "", s)                         # empty or doubled bold
    s = re.sub(r"\*\*(\s*)(.+?)(\s*)\*\*", r"\1**\2**\3", s)  # spaces inside bold
    s = re.sub(r"[ \t]+", " ", s).strip()
    s = URL.sub(lambda m: f"[{m.group(1)}]({m.group(1)})", s) if "](" not in s else s
    return s


def html_to_markdown(html: str) -> str:
    html = re.sub(r"<!--.*?-->", "", html, flags=re.S)
    p = _Md()
    p.feed(html)
    p.close()
    md = p.result()
    # "- " lists must start at the beginning of a block; numbered lists stay as lines in one paragraph
    return re.sub(r"\n{3,}", "\n\n", md).strip()


def sql_literal(s) -> str:
    if s is None:
        return "null"
    return "'" + str(s).replace("'", "''") + "'"
