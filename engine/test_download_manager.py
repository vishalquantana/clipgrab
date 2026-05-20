"""
Tests for download_manager.py

Run unit tests only:
    pytest engine/test_download_manager.py -v -m "not integration"

Run all tests (requires network + yt-dlp):
    pytest engine/test_download_manager.py -v
"""

import json
import subprocess
import sys
import os
import tempfile
import pytest

SCRIPT = os.path.join(os.path.dirname(__file__), "download_manager.py")


def run_dm(*args, cwd=None):
    """Run download_manager.py with the given arguments and return CompletedProcess."""
    return subprocess.run(
        [sys.executable, SCRIPT, *args],
        capture_output=True,
        text=True,
        cwd=cwd,
    )


def parse_json_lines(text):
    """Parse all JSON lines from stdout, ignoring blank lines."""
    lines = []
    for line in text.strip().splitlines():
        line = line.strip()
        if line:
            lines.append(json.loads(line))
    return lines


# ---------------------------------------------------------------------------
# URL validation tests
# ---------------------------------------------------------------------------


class TestInvalidURL:
    def test_invalid_url_exits_nonzero(self):
        result = run_dm("not-a-url", "--output-dir", "/tmp")
        assert result.returncode != 0, "Expected non-zero exit for invalid URL"

    def test_invalid_url_outputs_error_json(self):
        result = run_dm("not-a-url", "--output-dir", "/tmp")
        lines = parse_json_lines(result.stdout)
        assert len(lines) >= 1, "Expected at least one JSON line on stdout"
        err = lines[-1]
        assert err["type"] == "error"

    def test_invalid_url_error_has_required_fields(self):
        result = run_dm("not-a-url", "--output-dir", "/tmp")
        lines = parse_json_lines(result.stdout)
        err = lines[-1]
        assert "type" in err
        assert "message" in err
        assert "code" in err

    def test_invalid_url_error_code_is_string(self):
        result = run_dm("not-a-url", "--output-dir", "/tmp")
        lines = parse_json_lines(result.stdout)
        err = lines[-1]
        assert isinstance(err["code"], str), "code field must be a string"

    def test_ftp_url_is_invalid(self):
        result = run_dm("ftp://example.com/file.mp4", "--output-dir", "/tmp")
        assert result.returncode != 0
        lines = parse_json_lines(result.stdout)
        assert lines[-1]["type"] == "error"


class TestEmptyURL:
    def test_empty_url_exits_nonzero(self):
        result = run_dm("", "--output-dir", "/tmp")
        assert result.returncode != 0

    def test_empty_url_outputs_error_json(self):
        result = run_dm("", "--output-dir", "/tmp")
        lines = parse_json_lines(result.stdout)
        assert len(lines) >= 1
        assert lines[-1]["type"] == "error"

    def test_empty_url_error_has_required_fields(self):
        result = run_dm("", "--output-dir", "/tmp")
        lines = parse_json_lines(result.stdout)
        err = lines[-1]
        assert "type" in err
        assert "message" in err
        assert "code" in err


class TestMissingOutputDir:
    def test_missing_output_dir_arg_exits_nonzero(self):
        result = run_dm("https://example.com")
        # argparse will exit with code 2 when required arg is missing
        assert result.returncode != 0


class TestErrorJSONStructure:
    """Verify the error JSON contract for various bad inputs."""

    @pytest.mark.parametrize("bad_url", [
        "not-a-url",
        "",
        "ftp://example.com",
        "://broken",
        "javascript:alert(1)",
    ])
    def test_error_json_fields(self, bad_url):
        result = run_dm(bad_url, "--output-dir", "/tmp")
        assert result.returncode != 0
        lines = parse_json_lines(result.stdout)
        assert len(lines) >= 1, f"No JSON output for URL: {bad_url!r}"
        err = lines[-1]
        assert err.get("type") == "error", f"Expected type=error, got: {err}"
        assert "message" in err, "Missing 'message' field"
        assert "code" in err, "Missing 'code' field"
        assert isinstance(err["message"], str)
        assert isinstance(err["code"], str)


# ---------------------------------------------------------------------------
# Platform detection (no network needed — just URL pattern matching)
# ---------------------------------------------------------------------------


class TestPlatformDetection:
    """
    These tests verify that the script identifies the correct platform.
    We cannot actually download, so we rely on the script failing at the
    yt-dlp stage (or missing-dependency stage) rather than at URL validation.
    The important thing is that it does NOT fail with INVALID_URL.
    """

    def _get_error_code(self, url):
        result = run_dm(url, "--output-dir", "/tmp")
        lines = parse_json_lines(result.stdout)
        if lines and lines[-1]["type"] == "error":
            return lines[-1].get("code")
        return None

    @pytest.mark.parametrize("url", [
        "https://www.instagram.com/p/ABC123/",
        "https://www.instagram.com/reel/XYZ789/",
        "https://www.instagram.com/stories/user/123/",
    ])
    def test_instagram_urls_pass_validation(self, url):
        code = self._get_error_code(url)
        assert code != "INVALID_URL", f"URL wrongly rejected as invalid: {url}"

    @pytest.mark.parametrize("url", [
        "https://twitter.com/user/status/12345",
        "https://x.com/user/status/67890",
    ])
    def test_twitter_urls_pass_validation(self, url):
        code = self._get_error_code(url)
        assert code != "INVALID_URL", f"URL wrongly rejected as invalid: {url}"

    @pytest.mark.parametrize("url", [
        "https://www.linkedin.com/posts/someone_something",
        "https://www.linkedin.com/feed/update/urn:li:activity:123",
    ])
    def test_linkedin_urls_pass_validation(self, url):
        code = self._get_error_code(url)
        assert code != "INVALID_URL", f"URL wrongly rejected as invalid: {url}"


# ---------------------------------------------------------------------------
# Integration tests (require network + yt-dlp + ffmpeg)
# ---------------------------------------------------------------------------


@pytest.mark.integration
class TestIntegrationDownload:
    """
    Real download tests.  Skipped unless -m integration is passed.

    These use a short, publicly accessible video known to work with yt-dlp.
    Replace PLACEHOLDER_URL with an actual test URL before running.
    """

    PLACEHOLDER_URL = "https://www.youtube.com/watch?v=BaW_jenozKc"  # "youtube-dl test video"

    def test_download_produces_complete_event(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            result = run_dm(self.PLACEHOLDER_URL, "--output-dir", tmpdir)
            lines = parse_json_lines(result.stdout)
            types = [l["type"] for l in lines]
            assert "complete" in types, f"No 'complete' event in output. Lines: {lines}"

    def test_complete_event_has_required_fields(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            result = run_dm(self.PLACEHOLDER_URL, "--output-dir", tmpdir)
            lines = parse_json_lines(result.stdout)
            complete = next((l for l in lines if l["type"] == "complete"), None)
            assert complete is not None
            for field in ("file_path", "title", "platform", "media_type", "file_size", "thumbnail_path"):
                assert field in complete, f"Missing field: {field}"

    def test_downloaded_file_exists(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            result = run_dm(self.PLACEHOLDER_URL, "--output-dir", tmpdir)
            lines = parse_json_lines(result.stdout)
            complete = next((l for l in lines if l["type"] == "complete"), None)
            assert complete is not None
            assert os.path.isfile(complete["file_path"]), f"File not found: {complete['file_path']}"

    def test_progress_events_emitted(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            result = run_dm(self.PLACEHOLDER_URL, "--output-dir", tmpdir)
            lines = parse_json_lines(result.stdout)
            progress = [l for l in lines if l["type"] == "progress"]
            assert len(progress) > 0, "No progress events emitted"

    def test_progress_event_fields(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            result = run_dm(self.PLACEHOLDER_URL, "--output-dir", tmpdir)
            lines = parse_json_lines(result.stdout)
            progress = [l for l in lines if l["type"] == "progress"]
            if progress:
                p = progress[0]
                for field in ("percent", "downloaded_bytes", "total_bytes", "eta_seconds"):
                    assert field in p, f"Missing field '{field}' in progress event"
