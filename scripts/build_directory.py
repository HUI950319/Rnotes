"""Write the home-page note directory (_note-directory.md) from each chapter's front matter.

Every chapter in _quarto.yml declares either `directory: false` or

    directory:
      title: "目录里显示的标题"
      topic: 主题
      updated: 2026-10-18
      package: MLR        # only when it differs from the folder's package

Rows follow the book order. A chapter without `directory` stops the render, so new pages
cannot be left out of the home directory by accident.
"""

import re
import sys
from datetime import date
from pathlib import Path

import yaml

sys.dont_write_bytecode = True
from check_site import chapters

root = Path(__file__).resolve().parents[1]
packages = {"regr": "RegR", "mlr": "MLR", "utilsr": "UtilsR", "seerr": "seerR", "labr": "LabR",
            "scmmr": "scMMR", "toydata": "ToyData", "causalr": "causalR", "troubleshooting": "R 问题排查"}
config = yaml.safe_load((root / "_quarto.yml").read_text(encoding="utf-8-sig"))
rows, errors = [], []
for page in chapters(config["book"]["chapters"]):
    text = (root / page).read_text(encoding="utf-8")
    match = re.match(r"---\r?\n(.*?)\r?\n---", text, re.S)
    entry = (yaml.safe_load(match[1]) or {}).get("directory") if match else None
    if entry is False:
        continue
    if not isinstance(entry, dict) or not all(entry.get(k) for k in ("title", "topic", "updated")):
        errors.append(f"{page}: add `directory:` with title, topic and updated, or `directory: false`")
        continue
    updated = entry["updated"]
    if not isinstance(updated, date):
        errors.append(f"{page}: directory.updated must be a YYYY-MM-DD date")
        continue
    package = entry.get("package") or packages[page.split("/")[0]]
    title = str(entry["title"]).replace("|", r"\|")
    rows.append(f"| {package} | [{title}]({page}) | {entry['topic']} | {updated.isoformat()} |")
if errors:
    sys.exit("\n".join(errors))
table = "| 包 | 页面 | 主题 | 日期 |\n|:--|:--|:--|:--|\n" + "\n".join(rows) + "\n"
target = root / "_note-directory.md"
if not target.exists() or target.read_text(encoding="utf-8") != table:
    target.write_text(table, encoding="utf-8", newline="\n")
print(f"Wrote {len(rows)} directory rows")
