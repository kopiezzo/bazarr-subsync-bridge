#!/usr/bin/env python3
"""Bazarr SubSync Bridge: sync subtitles queued by the Bazarr hook with SubSync, one job at a time.

The Bazarr hook (bazarr-postprocess.sh) writes job-*.json files into the shared queue. This process
picks them up in order, runs SubSync against the video, replaces the subtitle atomically, and asks
Plex to rescan the folder. Run without arguments to process the queue, or with --health for the
container health check.
"""

from __future__ import annotations

import json
import logging
import logging.handlers
import os
import shutil
import signal
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path

# Fixed container paths. The BRIDGE_* overrides exist for the tests; 1.x configurations may still carry
# QUEUE_DIR and LOG_DIR with host paths, so those names are deliberately not read.
QUEUE_DIR = Path(os.environ.get("BRIDGE_QUEUE_DIR", "/queue"))
LOG_DIR = Path(os.environ.get("BRIDGE_LOG_DIR", "/logs"))
HEARTBEAT = Path(os.environ.get("BRIDGE_HEARTBEAT", "/tmp/bridge-heartbeat"))
SUBSYNC = os.environ.get("BRIDGE_SUBSYNC", "subsync")
POLL_SECONDS = 2
HEALTHY_SECONDS = 60

log = logging.getLogger("bridge")
stopping = False


def env_number(name: str, default: float) -> float:
    try:
        return float(os.environ.get(name, default))
    except ValueError:
        log.warning("%s is not a number, using %s", name, default)
        return default


@dataclass(frozen=True)
class Settings:
    effort: float = 0.5
    window: float = 600
    min_correlation: float = 0.5
    verbosity: int = 1
    timeout: float = 3600
    keep_backup: bool = False
    plex_url: str = ""
    plex_token: str = ""

    @classmethod
    def from_env(cls) -> "Settings":
        return cls(
            effort=env_number("SUBSYNC_EFFORT", 0.5),
            window=env_number("SUBSYNC_MAX_WINDOW", 600),
            min_correlation=env_number("SUBSYNC_MIN_CORRELATION", 0.5),
            verbosity=int(env_number("SUBSYNC_LOG_LEVEL", 1)),
            timeout=env_number("SUBSYNC_TIMEOUT", 3600),
            keep_backup=os.environ.get("SUBSYNC_KEEP_BACKUP", "0") not in ("", "0"),
            plex_url=os.environ.get("PLEX_URL", "").rstrip("/"),
            plex_token=os.environ.get("PLEX_TOKEN", ""),
        )


@dataclass(frozen=True)
class Job:
    video: Path
    subtitle: Path
    subtitle_lang: str = ""
    video_lang: str = ""


class InvalidJob(ValueError):
    pass


def read_job(path: Path) -> Job:
    """A queue file as a job; InvalidJob when it is not a usable job."""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as e:
        raise InvalidJob(f"unreadable job: {e}") from e
    if not isinstance(data, dict):
        raise InvalidJob("job is not a JSON object")
    fields = {}
    for key in ("video", "subtitle", "subtitle_lang", "video_lang"):
        value = data.get(key, "")
        if not isinstance(value, str):
            raise InvalidJob(f"{key} is not a string")
        fields[key] = value.strip()
    if not fields["video"] or not fields["subtitle"]:
        raise InvalidJob("job needs video and subtitle")
    if not (fields["video"].startswith("/") and fields["subtitle"].startswith("/")):
        raise InvalidJob("video and subtitle must be absolute paths")
    return Job(Path(fields["video"]), Path(fields["subtitle"]), fields["subtitle_lang"], fields["video_lang"])


def subsync_command(job: Job, output: Path, settings: Settings) -> list[str]:
    command = [SUBSYNC, "--cli", f"--verbose={settings.verbosity}", "sync", "--sub", str(job.subtitle)]
    if job.subtitle_lang:
        command += ["--sub-lang", job.subtitle_lang]
    command += ["--ref", str(job.video)]
    if job.video_lang:
        command += ["--ref-lang", job.video_lang]
    command += [
        "--out", str(output),
        f"--effort={settings.effort:g}",
        f"--window-size={settings.window:g}",
        f"--min-correlation={settings.min_correlation:g}",
        "--overwrite",
    ]
    return command


def run(command: list[str], timeout: float) -> int | None:
    """Run SubSync, log its output, and keep the heartbeat fresh. Returns the exit code, or None when SubSync
    was stopped on timeout or shutdown."""
    log.info("Running: %s", " ".join(command))
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace")
    reader = threading.Thread(target=forward, args=(process.stdout,), daemon=True)
    reader.start()
    deadline = time.monotonic() + timeout
    try:
        while True:
            beat()
            try:
                return process.wait(timeout=1)
            except subprocess.TimeoutExpired:
                pass
            if stopping or time.monotonic() > deadline:
                log.error("SubSync %s, stopping it", "interrupted by shutdown" if stopping else f"timed out after {timeout:g}s")
                return None
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        reader.join(5)


def forward(stream) -> None:
    with stream:
        for line in stream:
            if line.strip():
                log.info("subsync: %s", line.rstrip())


def sync(job: Job, settings: Settings) -> bool:
    """Synchronize one subtitle; the original is replaced only by a finished SubSync output."""
    for label, path in (("video", job.video), ("subtitle", job.subtitle)):
        if not path.is_file():
            log.error("%s file does not exist: %s", label.capitalize(), path)
            return False
    if job.subtitle.stat().st_size == 0:
        log.error("Subtitle file is empty: %s", job.subtitle)
        return False

    # Beside the subtitle, so the final rename is atomic; same extension, so SubSync keeps the format.
    output = job.subtitle.with_name(f".{job.subtitle.stem}.subsync{job.subtitle.suffix}")
    try:
        output.unlink(missing_ok=True)
        code = run(subsync_command(job, output, settings), settings.timeout)
        if code != 0:
            log.error("SubSync %s; subtitle left unchanged", "did not finish" if code is None else f"failed (code {code})")
            return False
        if not output.is_file() or output.stat().st_size == 0:
            log.error("SubSync did not write an output file; subtitle left unchanged")
            return False
        shutil.copymode(job.subtitle, output)
        if settings.keep_backup:
            backup = job.subtitle.with_name(f"{job.subtitle.name}.bak-{int(time.time())}")
            shutil.copy2(job.subtitle, backup)
            log.info("Backup kept: %s", backup)
        os.replace(output, job.subtitle)
        log.info("Synchronized: %s", job.subtitle)
        return True
    except OSError as e:
        log.error("Could not replace the subtitle, original kept: %s", e)
        return False
    finally:
        output.unlink(missing_ok=True)


class Plex:
    """Folder refresh in the Plex library section that holds the video."""

    def __init__(self, url: str, token: str):
        self.url, self.token = url, token
        self.sections: list[tuple[str, str]] | None = None

    def request(self, path: str) -> bytes:
        req = urllib.request.Request(self.url + path, headers={"X-Plex-Token": self.token, "Accept": "application/json"})
        with urllib.request.urlopen(req, timeout=15) as response:
            return response.read()

    def load_sections(self) -> list[tuple[str, str]]:
        """(location, section key) pairs, longest location first."""
        data = json.loads(self.request("/library/sections"))
        pairs = [
            (str(location.get("path", "")).rstrip("/"), str(section.get("key", "")))
            for section in data.get("MediaContainer", {}).get("Directory", [])
            for location in section.get("Location", [])
        ]
        pairs = [(location, key) for location, key in pairs if location and key]
        return sorted(pairs, key=lambda pair: len(pair[0]), reverse=True)

    def section_for(self, video: Path) -> str | None:
        for attempt in range(2):
            if self.sections is None or attempt:   # one reload when nothing matches: a library may be new
                self.sections = self.load_sections()
            for location, key in self.sections:
                if str(video).startswith(location + "/"):
                    return key
        return None

    def refresh(self, video: Path) -> None:
        if not self.url or not self.token:
            return
        try:
            key = self.section_for(video)
            if key is None:
                log.warning("Plex: no library section contains %s; Plex must see media under the same path", video.parent)
                return
            self.request(f"/library/sections/{key}/refresh?path={urllib.parse.quote(str(video.parent), safe='')}")
            log.info("Plex: refreshed section %s: %s", key, video.parent)
        except Exception as e:   # the refresh is a courtesy: whatever Plex answers, the job stays done
            log.warning("Plex refresh failed (check PLEX_URL and PLEX_TOKEN): %s", e)


def pending_jobs() -> list[Path]:
    """Queue files in arrival order (the hook names them job-<time>-<pid>.json). The hook writes *.json.tmp
    and renames it, so only finished jobs match."""
    return sorted(QUEUE_DIR.glob("*.json"))


def process(path: Path, settings: Settings, plex: Plex) -> None:
    log.info("Job: %s", path.name)
    try:
        job = read_job(path)
    except InvalidJob as e:
        log.error("Invalid job %s removed: %s", path.name, e)
        path.unlink(missing_ok=True)
        return
    log.info("Video: %s", job.video)
    log.info("Subtitle: %s (%s -> %s)", job.subtitle, job.subtitle_lang or "auto", job.video_lang or "auto")
    ok = sync(job, settings)
    if stopping and not ok:
        log.info("Shutdown: job %s stays queued", path.name)
        return
    path.unlink(missing_ok=True)
    if ok:
        plex.refresh(job.video)


def beat() -> None:
    HEARTBEAT.touch()


def healthy() -> bool:
    try:
        return time.time() - HEARTBEAT.stat().st_mtime < HEALTHY_SECONDS
    except OSError:
        return False


def setup_logging() -> None:
    formatter = logging.Formatter("%(asctime)s %(levelname)s %(message)s", "%Y-%m-%d %H:%M:%S")
    handlers: list[logging.Handler] = [logging.StreamHandler(sys.stdout)]
    try:
        handlers.append(logging.handlers.RotatingFileHandler(LOG_DIR / "bridge.log", maxBytes=10 << 20, backupCount=3))
    except OSError as e:
        print(f"Log file disabled: {e}", file=sys.stderr)
    for handler in handlers:
        handler.setFormatter(formatter)
        log.addHandler(handler)
    log.setLevel(logging.INFO)


def stop(_signum, _frame) -> None:
    global stopping
    stopping = True


def main() -> int:
    if sys.argv[1:] == ["--health"]:
        return 0 if healthy() else 1
    setup_logging()
    for folder in (QUEUE_DIR, LOG_DIR):
        if not os.access(folder, os.R_OK | os.W_OK | os.X_OK):
            log.error("%s must be readable and writable by uid %s", folder, os.getuid())
            return 1
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    settings = Settings.from_env()
    plex = Plex(settings.plex_url, settings.plex_token)
    log.info("Bazarr SubSync Bridge started: queue %s, Plex %s", QUEUE_DIR, "enabled" if plex.url and plex.token else "disabled")
    while not stopping:
        beat()
        for path in pending_jobs():
            if stopping:
                break
            try:
                process(path, settings, plex)
            except Exception:
                # A bug must not turn into a restart loop on the same job: log it and drop the job.
                log.exception("Unexpected error in job %s; job removed", path.name)
                path.unlink(missing_ok=True)
        time.sleep(POLL_SECONDS)
    log.info("Stopped by signal")
    return 0


if __name__ == "__main__":
    sys.exit(main())
