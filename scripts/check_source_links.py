"""Verify published HUI950319 package-source links using GitHub CLI."""

import re
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.parse import quote, unquote, urlparse

import yaml
from bs4 import BeautifulSoup

from check_site import chapters


REPOS = {"RegR", "MLR", "UtilsR", "seerR", "LabR", "scMMR", "ToyData", "causalR", "Rnotes"}


def endpoint(url):
    parsed = urlparse(url)
    if parsed.netloc != "github.com":
        return None
    parts = unquote(parsed.path).strip("/").split("/")
    if len(parts) < 4 or parts[0] != "HUI950319" or parts[1] not in REPOS:
        return None
    repo, kind, ref = parts[1:4]
    if kind in {"blob", "tree"}:
        path = "/".join(parts[4:])
        return f"repos/HUI950319/{repo}/contents/{quote(path, safe='/')}?ref={quote(ref, safe='')}"
    if kind == "commit" and re.fullmatch(r"[0-9a-f]{7,40}", ref):
        return f"repos/HUI950319/{repo}/commits/{ref}"
    return None


def verify(api_path):
    cli = ["wsl", "-d", "Ubuntu-22.04", "--", "gh"] if sys.platform == "win32" else ["gh"]
    for attempt in range(2):
        try:
            result = subprocess.run(cli + ["api", "--method", "HEAD", api_path],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                encoding="utf-8", errors="replace", timeout=25)
        except subprocess.TimeoutExpired:
            if attempt == 0:
                continue
            return "request timed out"
        if result.returncode == 0:
            return None
        error = result.stdout.strip()
        if "HTTP 404" in error or "HTTP 401" in error or attempt == 1:
            return error
        time.sleep(1)
    return "request failed"


def check(root):
    config = yaml.safe_load((root / "_quarto.yml").read_text(encoding="utf-8-sig"))
    docs = root / config["project"]["output-dir"]
    links = {}
    for chapter in chapters(config["book"]["chapters"]):
        page = docs / Path(chapter).with_suffix(".html")
        soup = BeautifulSoup(page.read_text(encoding="utf-8"), "html.parser")
        for a in soup.select("main a[href]"):
            api_path = endpoint(a["href"])
            if api_path:
                links.setdefault(api_path, set()).add((a["href"], chapter))
    failures = 0
    with ThreadPoolExecutor(max_workers=4) as pool:
        for api_path, error in zip(links, pool.map(verify, links)):
            if error:
                failures += 1
                for url, chapter in sorted(links[api_path]):
                    print(f"FAIL {chapter}: {url}")
                print(error)
    if failures:
        print(f"FAIL: {failures} unavailable source targets out of {len(links)}")
        return 1
    print(f"PASS: {len(links)} public package-source targets; files, directories and commit snapshots")
    return 0


if __name__ == "__main__":
    sys.dont_write_bytecode = True
    sys.exit(check(Path(__file__).resolve().parents[1]))
