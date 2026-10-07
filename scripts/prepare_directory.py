"""Add function keywords from Quarto's search index to the home directory."""

import json
import re
from collections import defaultdict
from html import escape
from pathlib import Path
from urllib.parse import unquote, urlparse

from bs4 import BeautifulSoup


docs = Path(__file__).resolve().parents[1] / "docs"
home = docs / "index.html"
document = home.read_text(encoding="utf-8")
keywords = defaultdict(set)
for item in json.loads((docs / "search.json").read_text(encoding="utf-8")):
    page = Path(unquote(urlparse(item["href"]).path)).as_posix()
    text = " ".join(item.get(field, "") for field in ("title", "section", "text"))
    keywords[page].update(re.findall(r"(?<![\w.])([A-Za-z.][A-Za-z0-9_.]*)\s*\(", text))


def prepare_row(match):
    row = match[0]
    link = BeautifulSoup(row, "html.parser").select_one("td a[href]")
    if link is None:
        return row
    page = Path(unquote(urlparse(link["href"]).path)).as_posix()
    value = escape(" ".join(sorted(keywords[page])), quote=True)
    opening = re.sub(r'\s+data-keywords="[^"]*"', "", row[:row.index(">")])
    return opening + f' data-keywords="{value}"' + row[row.index(">"):]


directory = re.search(r'<div\b[^>]*\bid="note-directory"[^>]*>.*?</div>', document, re.S)
prepared = re.sub(r"<tr\b[^>]*>.*?</tr>", prepare_row, directory[0], flags=re.S)
updated = document[:directory.start()] + prepared + document[directory.end():]
if updated != document:
    home.write_text(updated, encoding="utf-8")
print("Prepared home directory function keywords")
