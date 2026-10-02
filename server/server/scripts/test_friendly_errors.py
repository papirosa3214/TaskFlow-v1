"""MAK-13: сорвавшаяся загрузка источника отдаёт человеку понятную фразу, а не
сырой текст исключения. Run with python3 -m unittest test_friendly_errors
from server/scripts."""
import os
import re
import shutil
import subprocess
import tempfile
import unittest
import urllib.error
from unittest.mock import patch

import mcp_server as mcp

# Признаки «сырого» текста, которые не должны доехать до человека.
RAW = re.compile(r"Traceback|HTTPSConnectionPool|Errno|Command failed|yt-dlp:|ERROR:|0x[0-9a-f]{6,}")


def assert_human(case: unittest.TestCase, text: str) -> None:
    case.assertRegex(text, "[а-яА-ЯёЁ]")
    case.assertIsNone(RAW.search(text), text)


class YoutubeErrorTests(unittest.TestCase):
    def explain(self, stderr: str, code: int = 1) -> str:
        text = mcp._explain_youtube_error(stderr, code)
        assert_human(self, text)
        return text

    def test_no_subtitles(self):
        self.assertIn("нет субтитров", self.explain("", 0))
        self.assertIn(
            "нет субтитров",
            self.explain("WARNING: [youtube] abc: There are no subtitles for the requested languages", 0),
        )

    def test_bot_check_is_not_reported_as_no_subtitles(self):
        text = self.explain("ERROR: [youtube] abc: Sign in to confirm you’re not a bot. Use --cookies")
        self.assertIn("не робот", text)
        self.assertNotIn("нет субтитров", text)

    def test_age_restricted_is_not_bot_check(self):
        text = self.explain("ERROR: [youtube] abc: Sign in to confirm your age. This video may be inappropriate")
        self.assertIn("возрастным", text)

    def test_unavailable_and_private(self):
        self.assertIn("недоступно", self.explain("ERROR: [youtube] abc: Video unavailable"))
        self.assertIn("приватное", self.explain("ERROR: [youtube] abc: Private video. Sign in if you've been granted access"))

    def test_network(self):
        text = self.explain("ERROR: [youtube] abc: Unable to download webpage: <urlopen error [Errno 110] Connection timed out>")
        self.assertIn("Не удалось связаться с YouTube", text)

    def test_t_youtube_hides_stderr(self):
        stderr = "ERROR: [youtube] abc: Video unavailable. This video has been removed by the uploader"
        done = subprocess.CompletedProcess([], 1, stdout="", stderr=stderr)
        with patch.object(subprocess, "run", return_value=done):
            with self.assertRaises(mcp.TaskFlowError) as ctx:
                mcp.t_youtube({"url": "https://youtu.be/abc"})
        assert_human(self, str(ctx.exception))
        self.assertNotIn("uploader", str(ctx.exception))

    def test_t_youtube_timeout(self):
        with patch.object(subprocess, "run", side_effect=subprocess.TimeoutExpired("yt-dlp", 60)):
            with self.assertRaises(mcp.TaskFlowError) as ctx:
                mcp.t_youtube({"url": "https://youtu.be/abc"})
        self.assertIn("не ответил вовремя", str(ctx.exception))


class WebErrorTests(unittest.TestCase):
    URL = "https://example.org/page"

    def test_timeout(self):
        class ReadTimeout(Exception):
            pass
        text = mcp._explain_web_error(self.URL, ReadTimeout("HTTPSConnectionPool(host='example.org', port=443): Read timed out."))
        assert_human(self, text)
        self.assertIn("не ответил вовремя", text)
        self.assertIn("example.org", text)

    def test_connection_refused(self):
        text = mcp._explain_web_error(self.URL, urllib.error.URLError("[Errno 111] Connection refused"))
        assert_human(self, text)
        self.assertIn("Не удалось связаться", text)

    def test_http_statuses(self):
        class Response:
            def __init__(self, code):
                self.status_code = code

        class HTTPError(OSError):
            def __init__(self, code):
                super().__init__(f"{code} Client Error: for url: {WebErrorTests.URL}")
                self.response = Response(code)

        self.assertIn("такой страницы нет", mcp._explain_web_error(self.URL, HTTPError(404)))
        self.assertIn("не пускает", mcp._explain_web_error(self.URL, HTTPError(403)))
        self.assertIn("сбоит", mcp._explain_web_error(self.URL, HTTPError(503)))
        for code in (404, 403, 429, 503, 418):
            assert_human(self, mcp._explain_web_error(self.URL, HTTPError(code)))


@unittest.skipUnless(shutil.which("pdftotext"), "нужен pdftotext (poppler)")
class PdfErrorTests(unittest.TestCase):
    def test_broken_pdf(self):
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "broken.pdf")
            with open(path, "wb") as f:
                f.write(b"%PDF-1.4\n\x00\x01 garbage, not a real pdf \xff\xfe")
            with self.assertRaises(mcp.TaskFlowError) as ctx:
                mcp.t_ocr({"path": path})
        assert_human(self, str(ctx.exception))
        self.assertIn("PDF-файл повреждён", str(ctx.exception))

    def test_password_hint(self):
        self.assertIn("паролем", mcp._explain_pdf_error("Command Line Error: Incorrect password"))


class UnexpectedErrorTests(unittest.TestCase):
    def test_tools_call_hides_exception_text(self):
        def boom(_args):
            raise ValueError("invalid literal for int() with base 10: 'x' at 0x7f3a2b1c")

        tool = {"name": "boom", "description": "", "inputSchema": {}, "fn": boom}
        with patch.dict(mcp.BY_NAME, {"boom": tool}), \
                patch.object(mcp, "allowed_tool_names", return_value=None):
            out = mcp.handle({"jsonrpc": "2.0", "id": 1, "method": "tools/call",
                              "params": {"name": "boom", "arguments": {}}})
        text = out["result"]["content"][0]["text"]
        self.assertTrue(out["result"]["isError"])
        assert_human(self, text)
        self.assertNotIn("invalid literal", text)


if __name__ == "__main__":
    unittest.main()
