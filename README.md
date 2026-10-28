# Bazarr SubSync Bridge

Bazarr SubSync Bridge queues Bazarr post-processing jobs and runs [SubSync](https://github.com/sc0ty/subsync) on each subtitle file, one job at a time, with an optional Plex library refresh after a successful sync. It runs as a Docker container next to Bazarr and shares a queue directory with it.

## Layout

| Path | Contents |
| --- | --- |
| `bazarr-postprocess.sh` | Bazarr post-processing hook that writes a job to the shared queue |
| `bridge.py` | queue worker: SubSync run, atomic subtitle replace, Plex refresh, health check |
| `Dockerfile` | two-stage image: SubSync 0.17 built on Debian Bookworm, then a slim runtime |
| `patches/` | SubSync 0.17 patch for FFmpeg 5 |
| `docker-compose.yml`, `.env.example` | deployment and its settings |
| `tests/` | unit tests for `bridge.py` and the subtitles used by the end-to-end test |
| `.github/` | CI, release workflow, Dependabot, issue and pull request templates |

## Quick start

You need Docker with Compose, a media directory the container can read and write, and a Bazarr installation that can run a post-processing hook. Bazarr and the container must share a writable queue directory and see media under the same paths.

```bash
cp .env.example .env  # set MEDIA_HOST_PATH, MEDIA_CONTAINER_PATH, PUID, and PGID
mkdir -p queue logs   # default QUEUE_HOST_PATH and LOGS_HOST_PATH
docker compose pull
docker compose up -d
docker compose ps     # STATUS shows (healthy) after a few seconds
```

The image is published for `linux/amd64` and `linux/arm64` as `ghcr.io/kopiezzo/bazarr-subsync-bridge`. `docker compose up -d --build` builds it locally instead. Then configure the Bazarr hook as described in [Usage](#usage); the container alone only waits for jobs and does not download subtitles.

## Configuration

Settings are read from `.env`, created from [`.env.example`](.env.example).

| Variable | Purpose | Default |
| --- | --- | --- |
| `BRIDGE_VERSION` | image tag: `latest`, a major version such as `2`, or an exact release | `latest` |
| `MEDIA_HOST_PATH` | host directory with media files | none, set before starting |
| `MEDIA_CONTAINER_PATH` | the same directory inside the container; must match paths in Bazarr jobs | `/media` |
| `QUEUE_HOST_PATH` | host queue directory shared with Bazarr | `./queue` |
| `LOGS_HOST_PATH` | host directory for `bridge.log` | `./logs` |
| `PUID`, `PGID` | user and group the container runs as; match the owner of the queue, log, and subtitle directories | `1000`, `1000` |
| `SUBSYNC_QUEUE_DIR` | queue path seen by the Bazarr hook, set in Bazarr's environment | `/config/scripts/subsync-queue` |
| `SUBSYNC_EFFORT` | SubSync effort from 0 to 1; higher is slower and more accurate | `0.5` |
| `SUBSYNC_MAX_WINDOW` | largest correction SubSync searches, in seconds | `600` |
| `SUBSYNC_MIN_CORRELATION` | lowest correlation SubSync accepts as a match | `0.5` |
| `SUBSYNC_LOG_LEVEL` | SubSync verbosity from 0 to 3 | `1` |
| `SUBSYNC_TIMEOUT` | seconds after which a sync is stopped and counted as failed | `3600` |
| `SUBSYNC_KEEP_BACKUP` | nonzero keeps the original subtitle as `<name>.bak-<time>` after a successful sync | `0` |
| `PLEX_URL`, `PLEX_TOKEN` | optional Plex refresh; leave both empty to disable it | empty |

- **Host paths:** create the media, queue, and log directories before starting Compose. Compose fails when a bind source is missing instead of creating it with the wrong owner. Check `id -u` and `id -g` and set `PUID` and `PGID` to the owner of these directories.
- **Speech models:** SubSync downloads the speech recognition models it needs on first use. They are kept in the `cache` volume, so they are not downloaded again when the container is recreated.
- **Secrets:** keep `.env`, Plex tokens, logs, and queue payloads out of Git.
- **Trust boundary:** the queue is a trusted input. Only Bazarr or trusted automation should write to it.

## Usage

### Bazarr hook

Make `bazarr-postprocess.sh` available in Bazarr's scripts directory, preferably by mounting the version from this repository, and make it executable. Its `SUBSYNC_QUEUE_DIR` must resolve to the host directory mounted into the container as `/queue`. Set this Bazarr post-processing command:

```text
/config/scripts/bazarr-postprocess.sh {{episode}} {{subtitles}} {{subtitles_language_code3}} {{episode_language_code3}}
```

### Queue jobs

The hook writes `job-*.json` atomically. Jobs need `video` and `subtitle`; the language fields are optional and use the three-letter codes Bazarr provides.

```json
{
  "video": "/media/show/episode.mkv",
  "subtitle": "/media/show/episode.pl.srt",
  "subtitle_lang": "pol",
  "video_lang": "eng"
}
```

```text
Bazarr hook -> shared queue -> bridge.py -> SubSync -> subtitle replaced -> optional Plex refresh
```

- **Order:** the bridge checks the queue every 2 seconds and processes jobs one at a time, oldest first.
- **Languages:** `subtitle_lang` and `video_lang` are passed to SubSync, which uses the audio language to choose its speech model. An unknown code falls back to SubSync's own detection.
- **Sync:** SubSync writes its output beside the subtitle, with the same extension, so SRT, ASS, and SSA keep their format. The bridge replaces the subtitle atomically and keeps its file mode. A failed or timed-out sync leaves the original untouched.
- **Queue files:** the bridge removes the job file after every attempt, including a failed one, so failures are found in the log. A job interrupted by container shutdown stays queued and runs again after the restart.
- **Plex:** after a successful sync the bridge refreshes the folder in the Plex library section whose location contains the video. Plex must see media under the same path as the container. A failed refresh is logged and does not fail the job.

## Verification

```bash
python3 -m unittest discover -s tests
bash -n bazarr-postprocess.sh
docker compose config --quiet
docker compose build
```

After starting the service, download a subtitle in Bazarr and check that a `job-*.json` file appears in the shared queue and disappears after processing. `docker compose logs -f subsync` and `bridge.log` in the log directory show each job, the SubSync output, and the result. CI also runs a sync through the queue in the built container.

## Troubleshooting

- **`does not exist`:** Bazarr job paths do not match the container's media mount.
- **`must be readable and writable`:** the queue or log directory is not owned by `PUID`:`PGID`.
- **Queue not draining:** check the shared queue mount and confirm that job files end in `.json`.
- **`no library section contains`:** Plex sees the media under a different path than the container; align `MEDIA_CONTAINER_PATH` with the Plex library path.
- **`timed out`:** raise `SUBSYNC_TIMEOUT` or lower `SUBSYNC_EFFORT` for long videos.

## Deployment and rollback

Pin `BRIDGE_VERSION` to a major version, for example `2`, to get fixes without breaking changes. Update with `docker compose pull && docker compose up -d`. To roll back, set `BRIDGE_VERSION` to the previous release and run the same commands; the queue, logs, and the speech model cache are kept. Inspect any failed job in the log before queueing it again.

Version 2 replaced the shell monitor and Supervisor with `bridge.py`. When upgrading from 1.x, remove `PLEX_SECTION_SHOWS` and `PLEX_SECTION_MOVIES` from `.env` (the section now comes from Plex), and read logs from `bridge.log` instead of `monitor.log` and `subsync-exec.log`. `PUID` and `PGID` now set the container user at runtime, so the image no longer has to be rebuilt for another user.

## Documentation

- [`CONTRIBUTING.md`](CONTRIBUTING.md): branches, commit format, pull requests, and releases
- [`SECURITY.md`](SECURITY.md): private vulnerability reporting
- [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md): expectations for project discussions

## License

GPL-3.0, see [`LICENSE`](LICENSE).
