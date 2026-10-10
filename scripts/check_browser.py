"""Check representative published pages in Chromium, without re-running models."""

import functools
import threading
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from playwright.sync_api import sync_playwright


PAGES = [
    "index.html", "regr/facet-guide.html", "regr/rpa-guide.html",
    "regr/eff-cat-guide.html", "regr/interaction-guide.html", "mlr/index.html",
    "mlr/shap-guide.html", "utilsr/composition-guide.html",
    "utilsr/function-modules.html", "causalr/function-modules.html",
    "causalr/shap-guide.html",
]


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


def check_width(page, label):
    size = page.evaluate("""() => ({
        viewport: innerWidth, document: document.documentElement.scrollWidth
    })""")
    assert size["document"] <= size["viewport"] + 2, f"{label}: horizontal page overflow {size}"


def check(root):
    server = ThreadingHTTPServer(("127.0.0.1", 0),
        functools.partial(QuietHandler, directory=str(root / "docs")))
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    base = f"http://127.0.0.1:{server.server_port}/"
    tabs_checked = 0
    try:
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(headless=True)
            context = browser.new_context(viewport={"width": 1280, "height": 900},
                reduced_motion="reduce")
            # Local regression tests use fallback fonts and no external network.
            context.route("**/*", lambda route: route.continue_()
                if route.request.url.startswith(base) else route.abort())
            page = context.new_page()
            page.set_default_timeout(12000)
            errors = []
            page.on("pageerror", lambda error: errors.append(str(error)))
            for name in PAGES:
                response = page.goto(base + name, wait_until="load")
                assert response.ok, f"{name}: failed to load"
                assert page.locator("main").count() == 1, name
                assert page.locator("main .cell-output-error").count() == 0, name
                backgrounds = []
                for dark in (False, True):
                    page.set_viewport_size({"width": 1280, "height": 900})
                    is_dark = page.locator("body").evaluate("el => el.classList.contains('quarto-dark')")
                    if is_dark != dark:
                        page.locator(".quarto-color-scheme-toggle:visible").first.click()
                    page.wait_for_function("dark => document.body.classList.contains('quarto-dark') === dark", arg=dark)
                    # Quarto changes the body class before the alternate CSS loads.
                    page.wait_for_function("""dark => {
                        const mode = dark ? 'dark' : 'light';
                        const sheet = document.querySelector('link#quarto-bootstrap[data-mode="' + mode + '"]');
                        return sheet && sheet.rel === 'stylesheet' && sheet.sheet;
                    }""", arg=dark)
                    if backgrounds:
                        page.wait_for_function("light => getComputedStyle(document.body).backgroundColor !== light",
                            arg=backgrounds[0])
                    backgrounds.append(page.locator("body").evaluate("el => getComputedStyle(el).backgroundColor"))
                    check_width(page, f"{name} desktop dark={dark}")
                    page.set_viewport_size({"width": 390, "height": 844})
                    check_width(page, f"{name} mobile dark={dark}")
                    for tab in page.locator('[role="tab"]:visible').all():
                        tab.click()
                        assert tab.get_attribute("aria-selected") == "true", name
                        panel = page.locator("#" + tab.get_attribute("aria-controls"))
                        assert panel.is_visible(), f"{name}: tab panel not visible"
                        check_width(page, f"{name} tab={tab.inner_text()} dark={dark}")
                        tabs_checked += 1
                assert backgrounds[0] != backgrounds[1], f"{name}: theme did not change"
                if name == "index.html":
                    total = page.locator("#note-directory tbody tr").count()
                    page.locator("#note-package").select_option("RegR")
                    visible = page.locator("#note-directory tbody tr:not([hidden])")
                    assert 0 < visible.count() < total
                    assert all(row.locator("td").first.inner_text().strip() == "RegR"
                               for row in visible.all())
                    page.locator("#note-reset").click()
                    assert page.locator("#note-directory tbody tr:not([hidden])").count() == total
                assert not errors, f"{name}: JavaScript errors {errors}"
                print(f"PASS browser: {name}; desktop/mobile, light/dark and tabsets", flush=True)
            browser.close()
    finally:
        server.shutdown()
        server.server_close()
        thread.join()
    print(f"PASS: {len(PAGES)} representative pages; {tabs_checked} tab selections")


if __name__ == "__main__":
    check(Path(__file__).resolve().parents[1])
