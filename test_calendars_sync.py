import importlib.util
from importlib.machinery import SourceFileLoader
import io
import json
import sys
import tempfile
import unittest
from datetime import datetime
from pathlib import Path
from unittest.mock import patch
from zoneinfo import ZoneInfo


SCRIPT = Path(__file__).parent / "bin" / "calendars-sync"
SPEC = importlib.util.spec_from_loader(
    "calendars_sync", SourceFileLoader("calendars_sync", str(SCRIPT))
)
CALENDARS_SYNC = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CALENDARS_SYNC)


class FeedOperationTest(unittest.TestCase):
    def test_add_feed_reads_private_url_from_stdin(self):
        self.assertNotIn("CALENDARS_FEED_URL", SCRIPT.read_text())

        with tempfile.TemporaryDirectory() as directory:
            feeds = Path(directory) / "feeds.json"
            cache = Path(directory) / "events.json"
            request = {"action": "add", "url": "https://example.test/private-token", "name": "Private"}
            payload = {"ok": True, "configured": True, "feeds": [], "events": []}

            with (
                patch.object(sys, "argv", [str(SCRIPT), "--feeds", str(feeds), "--feed-operation-stdin"]),
                patch.object(sys, "stdin", io.StringIO(json.dumps(request) + "\n")),
                patch.object(sys, "stdout", io.StringIO()),
                patch.object(CALENDARS_SYNC, "sync", return_value=payload),
                patch.object(CALENDARS_SYNC, "result_path", return_value=str(cache)),
            ):
                self.assertEqual(CALENDARS_SYNC.main(), 0)

            saved = json.loads(feeds.read_text())
            self.assertEqual(saved[0]["url"], request["url"])

    def test_feed_storage_is_owner_only(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "private" / "feeds.json"
            CALENDARS_SYNC.save_feeds(path, [{
                "name": "Private",
                "url": "https://example.test/token",
                "color": "#8b7ff5",
                "enabled": True,
            }])

            self.assertEqual(path.parent.stat().st_mode & 0o777, 0o700)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_feed_storage_rejects_symlink_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            real = root / "real"
            real.mkdir()
            (root / "linked").symlink_to(real, target_is_directory=True)

            with self.assertRaises(OSError):
                CALENDARS_SYNC.save_feeds(root / "linked" / "feeds.json", [])

            self.assertFalse((real / "feeds.json").exists())

    def test_atomic_write_rejects_symlink_target(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            victim = root / "victim"
            victim.write_text("keep")
            target = root / "feeds.json"
            target.symlink_to(victim)

            with self.assertRaises(PermissionError):
                CALENDARS_SYNC.write_atomic(target, "replace")

            self.assertEqual(victim.read_text(), "keep")


class NetworkSecurityTest(unittest.TestCase):
    def test_loopback_address_is_rejected(self):
        answer = [(2, 1, 6, "", ("127.0.0.1", 443))]
        with patch.object(CALENDARS_SYNC.socket, "getaddrinfo", return_value=answer):
            address, error = CALENDARS_SYNC.resolve_public_ip("example.test", 443)

        self.assertIsNone(address)
        self.assertEqual(error, "resolves only to a private/internal address")

    def test_redirect_target_is_revalidated(self):
        private = "http://127.0.0.1/calendar"
        with patch.object(
            CALENDARS_SYNC,
            "fetch_one_hop",
            side_effect=[(None, private, None), (None, None, "private address rejected")],
        ) as fetch_one_hop:
            with patch.object(CALENDARS_SYNC, "read_cache", return_value=("", "blocked", False)):
                self.assertEqual(CALENDARS_SYNC.fetch("https://example.test/calendar"), ("", "blocked", False))

        self.assertEqual(fetch_one_hop.call_args_list[1].args[0], private)


class CalendarExpansionTest(unittest.TestCase):
    def test_weekly_recurrence_keeps_local_time_across_dst(self):
        calendar = """BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:dst-test
DTSTART;TZID=Europe/Monaco:20260323T090000
DTEND;TZID=Europe/Monaco:20260323T100000
RRULE:FREQ=WEEKLY;COUNT=3
SUMMARY:DST test
END:VEVENT
END:VCALENDAR
"""
        timezone = ZoneInfo("Europe/Monaco")
        events, _, _, _ = CALENDARS_SYNC.expand(
            calendar,
            {"name": "Test", "color": "#8b7ff5"},
            datetime(2026, 3, 20, tzinfo=timezone),
            datetime(2026, 4, 10, tzinfo=timezone),
            timezone,
        )

        self.assertEqual(
            [event["start"] for event in events],
            [
                "2026-03-23T09:00:00+01:00",
                "2026-03-30T09:00:00+02:00",
                "2026-04-06T09:00:00+02:00",
            ],
        )


if __name__ == "__main__":
    unittest.main()
