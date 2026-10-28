# Bazarr SubSync Bridge

Bazarr SubSync Bridge queues Bazarr post-processing jobs and runs [SubSync](https://github.com/sc0ty/subsync) on each subtitle file, one job at a time, with an optional Plex library refresh after a successful sync. It runs as a Docker container next to Bazarr and shares a queue directory with it.

## Layout

| Path | Contents |
| --- | --- |
| `bazarr-postprocess.sh` | Bazarr post-processing hook that writes a job to the shared queue |
| `subsync-monitor.sh` | queue monitor that processes jobs on startup and on filesystem events |
| `subsync-wrapper.sh` | one sync: subtitle backup, SubSync run, atomic replace, optional Plex refresh |
| `supervisord.conf` | process supervision for the monitor inside the container |
| `Dockerfile` | image based on Python 3.11 on Debian Bookworm, with SubSync and a health check |
| `patches/` | SubSync 0.17 patch for FFmpeg 5 |
| `docker-compose.yml`, `.env.example` | standalone deployment and its settings |
| `.github/` | CI, issue templates, and the pull request template |

## Quick start

You need Docker with Compose, a media directory the container can read and write, and a Bazarr installation that can run a post-processing hook. Bazarr and the container must share a writable queue directory and see media under the same paths.

```bash
cp .env.example .env  # set MEDIA_HOST_PATH, MEDIA_CONTAINER_PATH, PUID, and PGID
mkdir -p queue logs   # default QUEUE_HOST_PATH and LOGS_HOST_PATH
docker compose up -d --build
docker compose ps
```

Then configure the Bazarr hook as described in [Usage](#usage). The container alone only waits for jobs; it does not download subtitles.

## Configuration

Settings are read from `.env`, created from [`.env.example`](.env.example).

| Variable | Purpose | Default |
| --- | --- | --- |
| `MEDIA_HOST_PATH` | host directory with media files | none, set before starting |
| `MEDIA_CONTAINER_PATH` | the same directory inside the container; must match paths in Bazarr jobs | `/media` |
| `QUEUE_HOST_PATH` | host queue directory shared with Bazarr | `./queue` |
| `LOGS_HOST_PATH` | host directory for logs | `./logs` |
| `PUID`, `PGID` | user and group inside the container; match the owner of the queue, log, and subtitle directories | `1000`, `1000` |
| `SUBSYNC_QUEUE_DIR` | queue path seen by the Bazarr hook, set in Bazarr's environment | `/config/scripts/subsync-queue` |
| `PLEX_URL`, `PLEX_TOKEN` | optional Plex refresh; leave both empty to disable it | empty |
| `PLEX_SECTION_SHOWS`, `PLEX_SECTION_MOVIES` | Plex library section IDs | `1`, `2` |
| `SUBSYNC_LOG_LEVEL`, `SUBSYNC_EFFORT`, `SUBSYNC_MAX_WINDOW`, `SUBSYNC_MIN_CORRELATION` | sync tuning | `1`, `0.5`, `600`, `0.5` |
| `SUBSYNC_KEEP_BACKUP` | keep the subtitle backup after a successful sync | `0` |

- **Host paths:** create the media, queue, and log directories before starting Compose. Compose fails when a bind source is missing instead of creating it with the wrong owner. Check `id -u` and `id -g` and set `PUID` and `PGID` to the owner of these directories.
- **Container paths:** `/queue` and `/logs` are fixed inside the container. Old `QUEUE_DIR` and `LOG_DIR` entries in `.env` are ignored.
- **Secrets:** keep `.env`, Plex tokens, logs, and queue payloads out of Git.
- **Trust boundary:** the queue is a trusted input. Only Bazarr or trusted automation should write to it.

## Usage

### Bazarr hook

Make `bazarr-postprocess.sh` available in Bazarr's scripts directory, preferably by mounting the version from this repository, and make it executable. Its `SUBSYNC_QUEUE_DIR` must resolve to the host directory mounted into the container as `/queue`. Set this Bazarr post-processing command:

```text
/config/scripts/bazarr-postprocess.sh {{episode}} {{subtitles}} {{subtitles_language_code3}} {{episode_language_code3}}
```

### Queue jobs

The hook writes an atomic `job-*.json` file. Jobs require `video` and `subtitle`; language fields are optional.

```json
{
  "video": "/media/show/episode.mkv",
  "subtitle": "/media/show/episode.pl.srt",
  "subtitle_lang": "pol",
  "video_lang": "eng"
}
```

- **Startup:** the monitor processes existing jobs on startup and rescans the queue after filesystem events or a short timeout, so a job that arrives during startup is not stranded.
- **Sync:** the wrapper backs up the subtitle, writes the SubSync output beside it, and replaces the original atomically after success. A failed sync restores the original; a failed replace keeps the original and its backup.
- **Backups:** a successful run removes the backup unless `SUBSYNC_KEEP_BACKUP` is nonzero.
- **Queue files:** the monitor removes the job file after every attempt, including a failed one, so failures are found in the logs.
- **Plex:** a failed Plex refresh is logged and does not turn a successful sync into a failed job.

```text
Bazarr hook -> shared queue -> subsync-monitor.sh -> subsync-wrapper.sh -> optional Plex refresh
```

## Verification

```bash
bash -n bazarr-postprocess.sh subsync-monitor.sh subsync-wrapper.sh
docker compose config --quiet
docker build -t bazarr-subsync-bridge .
```

After starting the service, download a subtitle in Bazarr and confirm that a `job-*.json` file appears in the shared queue and is processed. Check `docker compose ps`, `docker compose logs -f subsync`, and `/logs/subsync-exec.log` inside the container.

## Troubleshooting

- **`File not found`:** Bazarr job paths do not match the container's media mount.
- **Queue not draining:** check the shared queue mount and confirm that job files end in `.json`.
- **Plex refresh skipped or failed:** check `PLEX_URL`, `PLEX_TOKEN`, and the section IDs. The subtitle sync can still succeed.

## Deployment and rollback

The included `docker-compose.yml` is a standalone deployment example. Keep the previous known-good image or commit before updating. If an update fails, redeploy that version with the same `.env` and the same queue, log, and media mounts, then run the checks from [Verification](#verification). Inspect any failed job before retrying it.

## Documentation

- [`CONTRIBUTING.md`](CONTRIBUTING.md): branches, commit format, pull requests, and releases
- [`SECURITY.md`](SECURITY.md): private vulnerability reporting
- [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md): expectations for project discussions

## License

GPL-3.0, see [`LICENSE`](LICENSE).
