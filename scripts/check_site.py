"""Check the published book before committing docs/ (no R execution needed)."""

import json
import re
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
            if "href" in item:
                yield item["href"]
            if str(item.get("part", "")).endswith(".qmd"):
                yield item["part"]
            yield from chapters(item.get("chapters", []))


def check(root):
    config = yaml.safe_load((root / "_quarto.yml").read_text(encoding="utf-8-sig"))
    docs = (root / config["project"]["output-dir"]).resolve()
    base = urlparse(config["book"]["site-url"])
    expected = [Path(p).with_suffix(".html").as_posix() for p in chapters(config["book"]["chapters"])]
    errors = []
    figure_numbers = {}

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
    expected_crumbs = {}

    def check_sidebar(items, container, page):
        children = container.select(":scope > li") if container else []
        name = page.relative_to(docs).as_posix()
        if len(children) != len(items):
            errors.append(f"{name}: sidebar level has {len(children)} items, expected {len(items)}")
        for item, child in zip(items, children):
            data = {"href": item} if isinstance(item, str) else item
            target = data.get("href", data.get("part", ""))
            path = docs / Path(target).with_suffix(".html") if target.endswith(".qmd") else None
            link = child.select_one(":scope > .sidebar-item-container > .sidebar-item-text")
            if path:
                title = pages.get(path).select_one("h1.title") if path in pages else None
                if path == docs / "index.html" and path in pages:
                    title = pages[path].select_one("main > section.level1 > h1") or title
                label = data.get("text") or (title.get_text(" ", strip=True) if title else target)
            else:
                label = data.get("text", target)
            if not link or link.get_text(" ", strip=True) != label:
                errors.append(f"{name}: sidebar label does not match {label}")
            if path and (not link or resolve(page, link.get("href", ""))[0] != path):
                errors.append(f"{name}: sidebar target does not match {target}")
            if "chapters" in data:
                section = child.select_one(":scope > ul.sidebar-section")
                check_sidebar(data["chapters"], section, page)
                for toggle in child.select(":scope > .sidebar-item-container > [data-bs-toggle='collapse']"):
                    expanded = section is not None and "show" in section.get("class", [])
                    if toggle.get("aria-expanded") != str(expanded).lower():
                        errors.append(f"{name}: inconsistent collapse state for {label}")
            elif child.select_one(":scope > ul"):
                errors.append(f"{name}: page {target} unexpectedly contains a sidebar section")

    for i, name in enumerate(expected):
        page = docs / name
        if not (root / Path(name).with_suffix(".qmd")).is_file() or page not in pages:
            errors.append(f"Missing chapter source or output: {name}")
            continue
        soup = pages[page]
        for caption in soup.select("main figcaption, main .figure-caption"):
            match = re.match(r"图\s+(\d+\.\d+)(?:\s|:|：)", caption.get_text(" ", strip=True))
            if not match:
                continue
            number = match[1]
            if int(number.split(".")[0]) != i:
                errors.append(f"{name}: figure {number} does not match chapter {i}")
            if number in figure_numbers:
                errors.append(f"Duplicate figure number {number}: {figure_numbers[number]} and {name}")
            else:
                figure_numbers[number] = name
        description = soup.select_one('head meta[name="description"]')
        if not description or not description.get("content", "").strip():
            errors.append(f"{name}: page description is missing")
        for direction, neighbor in (("previous", expected[i - 1] if i else None),
                                    ("next", expected[i + 1] if i + 1 < len(expected) else None)):
            links = soup.select(f"nav.page-navigation .nav-page-{direction} a[href]")
            actual = [resolve(page, a["href"])[0] for a in links]
            wanted = [docs / neighbor] if neighbor else []
            if actual != wanted:
                errors.append(f"{name}: {direction} should be {neighbor}, got {[p.relative_to(docs).as_posix() for p in actual]}")
            relation = "prev" if direction == "previous" else "next"
            head_links = soup.select(f'head link[rel="{relation}"][href]')
            if [resolve(page, a["href"])[0] for a in head_links] != wanted:
                errors.append(f"{name}: head {relation} does not match chapter order")
        sidebar = {resolve(page, a["href"])[0] for a in soup.select("#quarto-sidebar a[href]")
                   if resolve(page, a["href"]) is not None}
        missing = {docs / p for p in expected} - sidebar
        if missing:
            errors.append(f"{name}: sidebar is missing {len(missing)} chapters")
        check_sidebar(config["book"]["chapters"], soup.select_one("#quarto-sidebar .sidebar-menu-container > ul"), page)
        active = soup.select("#quarto-sidebar .sidebar-item-text.active[href]")
        if [resolve(page, a["href"])[0] for a in active] != [page]:
            errors.append(f"{name}: sidebar active item does not match the current page")
        if len(active) == 1:
            ancestors = [p for p in active[0].parents if p.name == "ul" and "sidebar-section" in p.get("class", [])]
            if any("show" not in p.get("class", []) for p in ancestors):
                errors.append(f"{name}: current page is hidden in a collapsed sidebar section")
            labels = [p.parent.select_one(":scope > .sidebar-item-container > .sidebar-item-text").get_text(" ", strip=True)
                      for p in reversed(ancestors)]
            labels.append(active[0].get_text(" ", strip=True))
            expected_crumbs[name] = labels
            for breadcrumb in soup.select(".quarto-page-breadcrumbs"):
                if [li.get_text(" ", strip=True) for li in breadcrumb.select("li")] != labels:
                    errors.append(f"{name}: breadcrumbs do not match sidebar ancestry")

    for page, soup in pages.items():
        for img in soup.select("main img[src]"):
            if not img.get("alt", "").strip():
                errors.append(f"{page.relative_to(docs)}: body figure is missing alternative text")
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

    # Overview counts must track the rendered tutorials, including new examples.
    overview = pages.get(docs / "mlr/index.html")
    if overview:
        for row in overview.select("main table tbody tr"):
            cells = row.select("td")
            link = cells[0].select_one("a[href]") if len(cells) == 2 else None
            count = re.fullmatch(r"(\d+)\s*张", cells[1].get_text(strip=True)) if len(cells) == 2 else None
            if link and count:
                target = resolve(docs / "mlr/index.html", link["href"])[0]
                if target in pages and int(count[1]) != len(pages[target].select("main figure")):
                    errors.append(f"mlr/index.html: outdated figure count for {link['href']}")

    search = json.loads((docs / "search.json").read_text(encoding="utf-8-sig"))
    for item in search:
        name = unquote(urlparse(item["href"]).path)
        if name not in expected_crumbs:
            continue
        crumbs = []
        for crumb in item.get("crumbs", []):
            label = BeautifulSoup(crumb, "html.parser")
            for number in label.select(".chapter-number"):
                number.decompose()
            crumbs.append(label.get_text(" ", strip=True))
        if crumbs != expected_crumbs[name]:
            errors.append(f"{item['href']}: search breadcrumbs do not match sidebar ancestry")
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
    print(f"PASS: {len(expected)} chapters; navigation, sidebar, descriptions, figure alt/lazy loading, local links, anchors, search and sitemap")
    return 0


if __name__ == "__main__":
    sys.exit(check(Path(__file__).resolve().parents[1]))
