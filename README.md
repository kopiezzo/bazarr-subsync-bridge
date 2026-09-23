# Bazarr SubSync Bridge

Bazarr SubSync Bridge queues Bazarr post-processing jobs and runs [SubSync](https://github.com/sc0ty/subsync) on subtitle files one job at a time. It can request a Plex library refresh after a successful sync. This repository contains the container, Bazarr hook, and a standalone Docker Compose configuration.

## Quick start

You need Docker with Compose, a media directory accessible to the container, and a Bazarr installation that can run a Python 3 post-processing hook. The Bazarr hook and container must share a writable queue directory and see the same media paths.

```bash
cp .env.example .env
# Set MEDIA_HOST_PATH and MEDIA_CONTAINER_PATH in .env.
docker compose up -d --build
docker compose ps
```

Configure Bazarr to run [`bazarr-postprocess.sh`](bazarr-postprocess.sh) and share its queue with the container as described in [Usage](#usage). The container alone waits for jobs; it does not download subtitles.

## Configuration

Copy [`.env.example`](.env.example) to `.env` and set the paths for your installation. The Compose file mounts `${MEDIA_HOST_PATH}` at `${MEDIA_CONTAINER_PATH}` and uses `./queue` and `./logs` by default for persistent queue and log storage.

| Setting | Purpose |
| --- | --- |
| `MEDIA_HOST_PATH` | Host directory containing media files; set this to a real path before starting. |
| `MEDIA_CONTAINER_PATH` | Path for that directory inside the container; it must match paths in Bazarr jobs. |
| `QUEUE_HOST_PATH` | Host queue directory shared with Bazarr; defaults to `./queue`. |
| `LOGS_HOST_PATH` | Host directory for logs; defaults to `./logs`. |
| `SUBSYNC_QUEUE_DIR` | Bazarr hook's queue path; set it in Bazarr's environment if its default `/config/scripts/subsync-queue` is not the shared directory. |
| `PLEX_URL`, `PLEX_TOKEN` | Optional Plex refresh; leave both empty to disable it. |
| `PLEX_SECTION_SHOWS`, `PLEX_SECTION_MOVIES` | Plex section IDs; defaults are `1` and `2`. |
| `SUBSYNC_*` | Optional sync tuning and backup behavior; defaults are in `.env.example`. |

`QUEUE_DIR` and `LOG_DIR` are container paths and normally stay at `/queue` and `/logs`. Keep `.env`, Plex tokens, logs, and queue payloads out of Git. The queue is a trusted input boundary: only Bazarr or trusted automation should write to it.

## Usage

Make `bazarr-postprocess.sh` available in Bazarr's scripts directory, preferably by mounting the version from this repository. Ensure it is executable and its `SUBSYNC_QUEUE_DIR` resolves to the same host directory mounted into the container as `/queue`. Bazarr and the container must use the same media path for each file.

Set this Bazarr post-processing command:

```text
/config/scripts/bazarr-postprocess.sh {{episode}} {{subtitles}} {{subtitles_language_code3}} {{episode_language_code3}}
```

The hook writes an atomic `job-*.json` file. The monitor processes existing jobs on startup, then watches for new files. Jobs require `video` and `subtitle`; language fields are optional. The wrapper backs up the subtitle before synchronization, writes its output beside the subtitle, and replaces the original atomically after success. A failed synchronization restores the original; a failed replacement keeps the original and its backup. A successful run removes the backup unless `SUBSYNC_KEEP_BACKUP` is nonzero. The monitor removes the queue file after an attempt, including a failed attempt; inspect logs for failures rather than expecting jobs to remain queued. Plex refresh failure is logged and does not turn a successful sync into a failed job.

Example queue payload:

```json
{
  "video": "/media/show/episode.mkv",
  "subtitle": "/media/show/episode.pl.srt",
  "subtitle_lang": "pol",
  "video_lang": "eng"
}
```

Runtime flow:

```text
Bazarr hook -> shared queue -> subsync-monitor.sh -> subsync-wrapper.sh -> optional Plex refresh
```

## Verification

Check shell syntax and the Compose configuration before deployment:

```bash
bash -n bazarr-postprocess.sh subsync-monitor.sh subsync-wrapper.sh
docker compose config --quiet
docker build -t bazarr-subsync-bridge .
```

After starting the service, run a Bazarr subtitle download and confirm a `job-*.json` file appears in the shared queue and is processed. Check `docker compose ps`, `docker compose logs -f subsync`, and the execution log in the configured log directory (`/logs/subsync-exec.log` inside the container). A failed sync is reported in the logs and its queue file is removed.

## Troubleshooting

- `File not found`: check that Bazarr job paths match the container's media mount.
- Queue not draining: check the shared queue mount and confirm jobs end in `.json`.
- Plex refresh skipped or failed: check `PLEX_URL`, `PLEX_TOKEN`, and section IDs. Subtitle sync can still succeed.

## Deployment and rollback

The included `docker-compose.yml` is a standalone deployment example; a production target and release process are not established in this repository. Keep the previous known-good image or commit before updating. If an update fails, redeploy that version using the same `.env` and persistent queue, log, and media mounts, then verify with the checks above. Preserve subtitle backups and inspect any failed job before retrying it.

## Documentation

- [`CONTRIBUTING.md`](CONTRIBUTING.md) explains branches, commits, and pull requests.
- [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) sets expectations for project discussions.
- [`SECURITY.md`](SECURITY.md) explains private vulnerability reporting.

## License

This project is licensed under GPL-3.0. See [`LICENSE`](LICENSE).
