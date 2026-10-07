"""Check the published book before committing docs/ (no R execution needed)."""

import json
import sys
from pathlib import Path
from urllib.parse import unquote, urlparse
from xml.etree import ElementTree as ET

import yaml
from bs4 import BeautifulSoup


def chapters(items):
    for item in items:
        if isinstance(item, str):
            yield item
        elif isinstance(item, dict):
            if str(item.get("part", "")).endswith(".qmd"):
                yield item["part"]
            yield from chapters(item.get("chapters", []))


def check(root):
    config = yaml.safe_load((root / "_quarto.yml").read_text(encoding="utf-8-sig"))
    docs = (root / config["project"]["output-dir"]).resolve()
    base = urlparse(config["book"]["site-url"])
    expected = [Path(p).with_suffix(".html").as_posix() for p in chapters(config["book"]["chapters"])]
    errors = []

    def resolve(page, url):
        parsed = urlparse(url)
        if parsed.scheme and parsed.scheme not in ("http", "https"):
            return None
        if parsed.netloc:
            if parsed.netloc != base.netloc or not parsed.path.startswith(base.path):
                return None
            target = docs / unquote(parsed.path[len(base.path):])
        elif parsed.path.startswith("/"):
            if not parsed.path.startswith(base.path):
                return None
            target = docs / unquote(parsed.path[len(base.path):])
        else:
            target = page.parent / unquote(parsed.path) if parsed.path else page
        if target.is_dir():
            target /= "index.html"
        return target.resolve(), unquote(parsed.fragment)

    pages = {
        p.resolve(): BeautifulSoup(p.read_text(encoding="utf-8-sig"), "html.parser")
        for p in docs.rglob("*.html") if "site_libs" not in p.relative_to(docs).parts
    }
    ids = {p: {t["id"] for t in soup.select("[id]")} | {t["name"] for t in soup.select("a[name]")}
           for p, soup in pages.items()}

    for i, name in enumerate(expected):
        page = docs / name
        if not (root / Path(name).with_suffix(".qmd")).is_file() or page not in pages:
            errors.append(f"Missing chapter source or output: {name}")
            continue
        soup = pages[page]
        for direction, neighbor in (("previous", expected[i - 1] if i else None),
                                    ("next", expected[i + 1] if i + 1 < len(expected) else None)):
            links = soup.select(f"nav.page-navigation .nav-page-{direction} a[href]")
            actual = [resolve(page, a["href"])[0] for a in links]
            wanted = [docs / neighbor] if neighbor else []
            if actual != wanted:
                errors.append(f"{name}: {direction} should be {neighbor}, got {[p.relative_to(docs).as_posix() for p in actual]}")
        sidebar = {resolve(page, a["href"])[0] for a in soup.select("#quarto-sidebar a[href]")
                   if resolve(page, a["href"]) is not None}
        missing = {docs / p for p in expected} - sidebar
        if missing:
            errors.append(f"{name}: sidebar is missing {len(missing)} chapters")

    for page, soup in pages.items():
        for img in soup.select("main img[src]"):
            if img.get("loading") != "lazy":
                errors.append(f"{page.relative_to(docs)}: body figure is missing lazy loading")
            for candidate in img.get("srcset", "").split(","):
                if candidate.strip():
                    result = resolve(page, candidate.strip().split()[0])
                    if result and not result[0].is_file():
                        errors.append(f"{page.relative_to(docs)}: missing figure preview {candidate}")
        for tag in soup.select("a[href], link[href], img[src], script[src], iframe[src], source[src], video[src], object[data]"):
            url = tag.get("href", tag.get("src", tag.get("data")))
            result = resolve(page, url)
            if result is None:
                continue
            target, fragment = result
            label = page.relative_to(docs).as_posix()
            if not target.is_file():
                errors.append(f"{label}: missing local target {url}")
            elif target.suffix == ".qmd":
                errors.append(f"{label}: published link still points to source {url}")
            elif fragment and not fragment.startswith(":~:") and target in ids and fragment not in ids[target]:
                errors.append(f"{label}: missing anchor {url}")

    search = json.loads((docs / "search.json").read_text(encoding="utf-8-sig"))
    search_pages = {unquote(urlparse(item["href"]).path) for item in search}
    sitemap = ET.parse(docs / "sitemap.xml")
    sitemap_pages = {urlparse(loc.text).path[len(base.path):]
                     for loc in sitemap.findall(".//{*}loc")}
    for name, indexed in (("search.json", search_pages), ("sitemap.xml", sitemap_pages)):
        if indexed != set(expected):
            errors.append(f"{name}: missing={sorted(set(expected) - indexed)}, extra={sorted(indexed - set(expected))}")

    if errors:
        print("\n".join(errors))
        print(f"FAIL: {len(errors)} issues")
        return 1
    print(f"PASS: {len(expected)} chapters; navigation, sidebar, local links, anchors, search and sitemap")
    return 0


if __name__ == "__main__":
    sys.exit(check(Path(__file__).resolve().parents[1]))
