import subprocess
import time
import signal
import pytest
from playwright.sync_api import sync_playwright

APP_URL = "http://localhost:8000"


@pytest.fixture(scope="module")
def flask_server():
    """Start the Flask app in a subprocess for E2E testing."""
    proc = subprocess.Popen(
        ["python", "app.py"],
        cwd="src/hello-world",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    time.sleep(2)  # wait for server to start
    yield proc
    proc.send_signal(signal.SIGTERM)
    proc.wait(timeout=5)


def test_page_loads_with_hello_world(flask_server):
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()
        page.goto(APP_URL)

        heading = page.locator("h1")
        assert heading.inner_text() == "Hello World!"

        browser.close()


def test_globe_image_visible(flask_server):
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()
        page.goto(APP_URL)

        globe = page.locator("img[alt='Globe']")
        assert globe.is_visible()

        browser.close()


def test_subtitle_text_present(flask_server):
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()
        page.goto(APP_URL)

        subtitle = page.locator(".subtitle")
        assert "Azure starter project" in subtitle.inner_text()

        browser.close()
