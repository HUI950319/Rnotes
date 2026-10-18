"""Move JavaScript libraries repeated across self-contained widget pages into assets/widget-libs/.

htmlwidgets saved with selfcontained = TRUE inline plotly.js (about 3.6 MB) into every page.
An inline <script> block is moved when its exact text already exists in assets/widget-libs/
or occurs in at least two widget pages; it becomes <script src="..."></script> in place.
Source pages and their docs/ copies are rewritten the same way. Run after adding widget pages.
"""

import hashlib
import os
import re
from collections import Counter
from pathlib import Path

root = Path(__file__).resolve().parents[1]
libdir = "assets/widget-libs"
script = re.compile(r"<script>(.*?)</script>", re.S)
names = [(r"plotly\.js v([\d.]+)", "plotly-{}"), (r"jQuery v([\d.]+)", "jquery-{}"),
         (r'HTMLWidgets\.widget\(\{\s*name: "plotly"', "plotly-binding"),
         (r"window\.HTMLWidgets is already defined", "htmlwidgets"),
         (r"MAX_ARRAY_LENGTH", "typedarray")]


def digest(body):
    return hashlib.sha1(body.encode("utf-8")).hexdigest()[:10]


def lib_name(body):
    for pattern, name in names:
        match = re.search(pattern, body[:200])
        if match:
            return f"{name.format(*match.groups())}-{digest(body)}.js"
    return f"lib-{digest(body)}.js"


pages = {}
for base in (root, root / "docs"):
    for path in base.rglob("*.html"):
        rel = path.relative_to(root).as_posix()
        if any(part in rel for part in ("site_libs/", ".quarto/", "_freeze/")) or (
                base == root and rel.startswith("docs/")):
            continue
        text = path.read_text(encoding="utf-8")
        if "quarto-sidebar" not in text and "HTMLWidgets" in text and script.search(text):
            pages[path] = text

existing = {path.read_text(encoding="utf-8"): path.name for path in (root / libdir).glob("*.js")}
blocks = {}  # a source page and its docs/ copy count as one page
for path, text in pages.items():
    page = path.relative_to(root).as_posix().removeprefix("docs/")
    blocks.setdefault(page, set()).update(
        m.group(1) for m in script.finditer(text) if len(m.group(1)) > 10_000)
count = Counter(body for found in blocks.values() for body in found)
shared = {body: existing.get(body) or lib_name(body)
          for body, n in count.items() if body in existing or n >= 2}

for body, name in shared.items():
    for base in (root, root / "docs"):
        target = base / libdir / name
        if not target.exists():
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(body, encoding="utf-8", newline="")

for path, text in pages.items():
    base = root / "docs" if path.is_relative_to(root / "docs") else root
    rel = Path(os.path.relpath(base / libdir, path.parent)).as_posix()
    new = script.sub(lambda m: f'<script src="{rel}/{shared[m.group(1)]}"></script>'
                     if m.group(1) in shared else m.group(0), text)
    if new != text:
        path.write_text(new, encoding="utf-8", newline="")
        print(f"{path.relative_to(root).as_posix()}: {len(text) // 1024} KB -> {len(new) // 1024} KB")
