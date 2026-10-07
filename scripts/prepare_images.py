"""Add lazy loading and pixel-identical WebP previews to rendered figures."""

import hashlib
import html
import io
import os
import re
import shutil
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.parse import unquote, urlparse

import yaml
from bs4 import BeautifulSoup
from PIL import Image

sys.dont_write_bytecode = True
from check_site import chapters


root = Path(__file__).resolve().parents[1]
config = yaml.safe_load((root / "_quarto.yml").read_text(encoding="utf-8-sig"))
docs = root / config["project"]["output-dir"]
pages = [docs / Path(p).with_suffix(".html") for p in chapters(config["book"]["chapters"])]
originals = set()
for page in pages:
    if page.is_file():
        soup = BeautifulSoup(page.read_text(encoding="utf-8"), "html.parser")
        for img in soup.select("main img[src]"):
            url = urlparse(img["src"])
            path = (page.parent / unquote(url.path)).resolve()
            if not url.scheme and path.is_file() and path.suffix.lower() == ".png":
                originals.add(path)


def preview(path):
    data = path.read_bytes()
    name = hashlib.sha256(data).hexdigest()[:32] + ".webp"
    source = root / "assets/figure-previews" / name
    with Image.open(io.BytesIO(data)) as image:
        size = image.size
        if not source.exists():
            encoded = io.BytesIO()
            image.save(encoded, "WEBP", lossless=True, exact=True, method=1)
            encoded = encoded.getvalue()
            if len(encoded) >= len(data):
                return path, size, None
            with Image.open(io.BytesIO(encoded)) as decoded:
                assert decoded.size == size and decoded.convert("RGBA").tobytes() == image.convert("RGBA").tobytes(), path
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_bytes(encoded)
    output = docs / "assets/figure-previews" / name
    output.parent.mkdir(parents=True, exist_ok=True)
    if not output.exists() or output.read_bytes() != source.read_bytes():
        shutil.copy2(source, output)
    return path, size, output


with ThreadPoolExecutor(max_workers=4) as pool:
    figures = {path: (size, output) for path, size, output in pool.map(preview, sorted(originals))}

count = 0
changed = 0
for page in pages:
    if not page.is_file():
        continue
    text = page.read_text(encoding="utf-8")
    main = re.search(r"<main\b.*?</main>", text, re.S)
    if not main:
        continue

    def optimize(match):
        global count
        raw = match.group()
        img = BeautifulSoup(raw, "html.parser").img
        attrs = {"loading": "lazy", "decoding": "async"}
        path = (page.parent / unquote(urlparse(img.get("src", "")).path)).resolve()
        if path in figures:
            (width, height), output = figures[path]
            if not img.has_attr("width"):
                attrs["width"] = str(width)
            if not img.has_attr("height"):
                attrs["height"] = str(height)
            if output:
                # Keep src and the surrounding lightbox link on the original PNG.
                attrs["srcset"] = os.path.relpath(output, page.parent).replace("\\", "/")
        for name, value in attrs.items():
            pattern = r"\s" + re.escape(name) + r'="[^"]*"'
            attribute = f' {name}="{html.escape(value, quote=True)}"'
            raw = re.sub(pattern, lambda _: attribute, raw) if re.search(pattern, raw) else raw[:-1].rstrip("/") + attribute + ">"
        count += 1
        return raw

    body = re.sub(r"<img\b[^>]*>", optimize, main.group())
    updated = text[:main.start()] + body + text[main.end():]
    if updated != text:
        page.write_text(updated, encoding="utf-8", newline="\n")
        changed += 1

optimized = [(path, output) for path, (_, output) in figures.items() if output]
before = sum(path.stat().st_size for path, _ in optimized)
after = sum(output.stat().st_size for _, output in optimized)
print(f"Figures: {count} lazy; {len(optimized)} pixel-identical WebP previews; {changed} HTML pages updated")
print(f"Preview transfer: {before / 1024 ** 2:.2f} -> {after / 1024 ** 2:.2f} MiB (original PNGs retained)")
