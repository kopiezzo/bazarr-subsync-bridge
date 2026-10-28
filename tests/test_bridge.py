"""Tests for bridge.py with a stand-in SubSync. Run: python3 -m unittest discover tests"""

import http.server
import importlib
import json
import os
import sys
import tempfile
import threading
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

# A stand-in for SubSync: writes "synced:" plus the subtitle to --out, or fails when FAKE_SUBSYNC_FAIL is set.
FAKE_SUBSYNC = """#!/usr/bin/env python3
import os, sys, time
args = sys.argv[1:]
open(os.environ["FAKE_SUBSYNC_ARGS"], "w").write("\\n".join(args))
if os.environ.get("FAKE_SUBSYNC_SLEEP"):
    time.sleep(float(os.environ["FAKE_SUBSYNC_SLEEP"]))
if os.environ.get("FAKE_SUBSYNC_FAIL"):
    print("no correlation")
    sys.exit(2)
sub = open(args[args.index("--sub") + 1]).read()
open(args[args.index("--out") + 1], "w").write("synced:" + sub)
print("done")
"""


class BridgeTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.queue, self.logs, self.media = root / "queue", root / "logs", root / "media"
        for folder in (self.queue, self.logs, self.media):
            folder.mkdir()
        fake = root / "subsync"
        fake.write_text(FAKE_SUBSYNC)
        fake.chmod(0o755)
        self.args = root / "args.txt"
        self.env = {
            "QUEUE_DIR": str(self.queue), "LOG_DIR": str(self.logs), "HEARTBEAT_FILE": str(root / "beat"),
            "SUBSYNC_COMMAND": str(fake), "FAKE_SUBSYNC_ARGS": str(self.args),
        }
        self.saved = {k: os.environ.get(k) for k in [*self.env, "FAKE_SUBSYNC_FAIL", "FAKE_SUBSYNC_SLEEP"]}
        os.environ.update(self.env)
        import bridge
        self.bridge = importlib.reload(bridge)
        self.video = self.media / "Show" / "episode.mkv"
        self.video.parent.mkdir()
        self.video.write_bytes(b"video")

    def tearDown(self):
        for key, value in self.saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        self.tmp.cleanup()

    def subtitle(self, name="episode.pl.srt", text="1\n00:00:01,000 --> 00:00:02,000\nHi\n"):
        path = self.video.parent / name
        path.write_text(text)
        return path

    def queue_job(self, name="job-1-1.json", **fields):
        path = self.queue / name
        path.write_text(json.dumps(fields))
        return path

    def test_read_job(self):
        job = self.bridge.read_job(self.queue_job(video="/m/v.mkv", subtitle="/m/v.srt", subtitle_lang="pol"))
        self.assertEqual((str(job.video), str(job.subtitle), job.subtitle_lang, job.video_lang), ("/m/v.mkv", "/m/v.srt", "pol", ""))

    def test_invalid_jobs(self):
        for name, text in (("a.json", "{"), ("b.json", "[]"), ("c.json", '{"video": "x"}'), ("d.json", '{"video": 1, "subtitle": "s"}')):
            path = self.queue / name
            path.write_text(text)
            with self.assertRaises(self.bridge.InvalidJob):
                self.bridge.read_job(path)

    def test_command_passes_languages(self):
        job = self.bridge.Job(Path("/m/v.mkv"), Path("/m/v.srt"), "pol", "eng")
        command = self.bridge.subsync_command(job, Path("/m/.v.subsync.srt"), self.bridge.Settings())
        self.assertEqual(command[command.index("--sub-lang") + 1], "pol")
        self.assertEqual(command[command.index("--ref-lang") + 1], "eng")
        self.assertLess(command.index("sync"), command.index("--sub"))

    def test_command_without_languages(self):
        command = self.bridge.subsync_command(self.bridge.Job(Path("v"), Path("s")), Path("o"), self.bridge.Settings())
        self.assertNotIn("--sub-lang", command)
        self.assertNotIn("--ref-lang", command)

    def test_sync_replaces_subtitle_and_keeps_format_and_mode(self):
        sub = self.subtitle("episode.pl.ass", "[Script Info]\n")
        sub.chmod(0o640)
        ok = self.bridge.sync(self.bridge.Job(self.video, sub, "pol"), self.bridge.Settings())
        self.assertTrue(ok)
        self.assertEqual(sub.read_text(), "synced:[Script Info]\n")
        self.assertEqual(sub.stat().st_mode & 0o777, 0o640)
        out = self.args.read_text().split("\n")
        self.assertTrue(out[out.index("--out") + 1].endswith(".subsync.ass"))
        self.assertEqual(sorted(p.name for p in sub.parent.iterdir()), ["episode.mkv", "episode.pl.ass"])

    def test_sync_keeps_backup_when_asked(self):
        sub = self.subtitle()
        self.assertTrue(self.bridge.sync(self.bridge.Job(self.video, sub), self.bridge.Settings(keep_backup=True)))
        backups = list(sub.parent.glob("episode.pl.srt.bak-*"))
        self.assertEqual(len(backups), 1)
        self.assertFalse(backups[0].read_text().startswith("synced:"))

    def test_failed_sync_leaves_subtitle(self):
        os.environ["FAKE_SUBSYNC_FAIL"] = "1"
        sub = self.subtitle()
        before = sub.read_text()
        self.assertFalse(self.bridge.sync(self.bridge.Job(self.video, sub), self.bridge.Settings()))
        self.assertEqual(sub.read_text(), before)
        self.assertEqual(sorted(p.name for p in sub.parent.iterdir()), ["episode.mkv", "episode.pl.srt"])

    def test_missing_and_empty_files(self):
        settings = self.bridge.Settings()
        self.assertFalse(self.bridge.sync(self.bridge.Job(self.video, self.video.parent / "none.srt"), settings))
        self.assertFalse(self.bridge.sync(self.bridge.Job(self.video, self.subtitle(text="")), settings))
        self.assertFalse(self.args.exists())

    def test_timeout_stops_subsync(self):
        os.environ["FAKE_SUBSYNC_SLEEP"] = "30"
        sub = self.subtitle()
        self.assertFalse(self.bridge.sync(self.bridge.Job(self.video, sub), self.bridge.Settings(timeout=1)))
        self.assertFalse(sub.read_text().startswith("synced:"))

    def test_queue_order_ignores_partial_jobs(self):
        for name in ("job-2-1.json", "job-1-9.json", "job-3-1.json.tmp"):
            (self.queue / name).write_text("{}")
        self.assertEqual([p.name for p in self.bridge.pending_jobs()], ["job-1-9.json", "job-2-1.json"])

    def test_process_removes_job_and_refreshes_plex(self):
        sub = self.subtitle()
        job = self.queue_job(video=str(self.video), subtitle=str(sub))
        refreshed = []
        plex = type("Plex", (), {"refresh": lambda self, video: refreshed.append(video)})()
        self.bridge.process(job, self.bridge.Settings(), plex)
        self.assertFalse(job.exists())
        self.assertEqual(refreshed, [self.video])

    def test_shutdown_keeps_job(self):
        os.environ["FAKE_SUBSYNC_SLEEP"] = "30"
        job = self.queue_job(video=str(self.video), subtitle=str(self.subtitle()))
        threading.Timer(1.5, lambda: setattr(self.bridge, "stopping", True)).start()
        self.bridge.process(job, self.bridge.Settings(), self.bridge.Plex("", ""))
        self.assertTrue(job.exists())

    def test_health(self):
        self.assertFalse(self.bridge.healthy())
        self.bridge.beat()
        self.assertTrue(self.bridge.healthy())


class PlexTest(unittest.TestCase):
    def setUp(self):
        self.requests = []
        sections = {"MediaContainer": {"Directory": [
            {"key": "1", "Location": [{"path": "/media/tv"}]},
            {"key": "2", "Location": [{"path": "/media"}, {"path": "/films/"}]},
            {"key": "3"},
        ]}}
        test = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                test.requests.append((self.path, self.headers.get("X-Plex-Token")))
                body = json.dumps(sections).encode() if self.path == "/library/sections" else b""
                self.send_response(200)
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *args):
                pass

        self.server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        import bridge
        self.plex = bridge.Plex(f"http://127.0.0.1:{self.server.server_port}", "secret")

    def tearDown(self):
        self.server.shutdown()

    def test_longest_location_wins(self):
        self.assertEqual(self.plex.section_for(Path("/media/tv/Show/e.mkv")), "1")
        self.assertEqual(self.plex.section_for(Path("/media/movies/m.mkv")), "2")
        self.assertEqual(self.plex.section_for(Path("/films/m.mkv")), "2")
        self.assertIsNone(self.plex.section_for(Path("/mediaX/m.mkv")))

    def test_refresh_sends_token_and_encoded_folder(self):
        self.plex.refresh(Path("/media/tv/My Show/e 1.mkv"))
        self.assertIn(("/library/sections/1/refresh?path=%2Fmedia%2Ftv%2FMy%20Show", "secret"), self.requests)

    def test_refresh_survives_unreachable_plex(self):
        import bridge
        bridge.Plex("http://127.0.0.1:9", "secret").refresh(Path("/media/x.mkv"))


if __name__ == "__main__":
    unittest.main()
