# Bazarr SubSync Bridge

Queue-based Bazarr post-processing bridge for
[SubSync](https://github.com/sc0ty/subsync). Bazarr writes jobs, this service
processes them one at a time, and Plex can be refreshed after successful sync.

## What It Is

- Watches a shared queue directory for `*.json` jobs.
- Validates each job before processing.
- Runs `subsync` for a video/subtitle pair.
- Keeps failed jobs and logs for diagnostics.
- Optionally refreshes Plex libraries.
- Drains existing queue jobs on startup.

## Runtime

```text
Bazarr post-process hook -> queue file -> subsync-monitor.sh -> subsync-wrapper.sh
```

Important paths inside the container:

- queue: `/queue`
- logs: `/logs`
- media: configured by `MEDIA_CONTAINER_PATH`

## Quickstart

```bash
cp .env.example .env
```

Set at least:

- `MEDIA_HOST_PATH`
- `MEDIA_CONTAINER_PATH`

Optional Plex integration:

- `PLEX_URL`
- `PLEX_TOKEN`
- `PLEX_SECTION_SHOWS`
- `PLEX_SECTION_MOVIES`

Start:

```bash
docker compose up -d --build
docker compose ps
```

## Bazarr Setup

Post-processing command:

```text
/config/scripts/bazarr-postprocess.sh {{episode}} {{subtitles}} {{subtitles_language_code3}} {{episode_language_code3}}
```

Checklist:

- `bazarr-postprocess.sh` exists in Bazarr's scripts directory.
- The script is executable.
- Prefer mounting this repository's `bazarr-postprocess.sh` directly into Bazarr
  so the runtime hook cannot drift from source control.
- Bazarr writes queue files to a directory shared with this service.
- The same host media path is mounted into Bazarr and this container.
- A test subtitle download creates a `job-*.json` file and it is processed.

## Job Format

```json
{
  "video": "/media/show/episode.mkv",
  "subtitle": "/media/show/episode.pl.srt",
  "subtitle_lang": "pol",
  "video_lang": "eng"
}
```

Required keys:

- `video`
- `subtitle`

## Operations

Watch logs:

```bash
docker compose logs -f subsync
```

Inspect execution log:

```text
/logs/subsync-exec.log
```

Common failures:

- `File not found`: Bazarr and this container do not share the same media mapping.
- queue not draining: queue mount is wrong or files do not end with `.json`.
- Plex refresh skipped: Plex variables are missing or invalid; subtitle sync can still succeed.

## Verify

```bash
bash -n bazarr-postprocess.sh
bash -n subsync-monitor.sh
bash -n subsync-wrapper.sh
docker compose config --quiet
docker build -t bazarr-subsync-bridge .
```

## Security Notes

- Treat `/queue` as a trusted input boundary.
- Only Bazarr or trusted automation should write queue jobs.
- Never commit `.env`, Plex tokens, logs, or internal paths you do not want public.

## Project Files

- `bazarr-postprocess.sh` - Bazarr hook that writes queue jobs.
- `subsync-monitor.sh` - queue watcher and dispatcher.
- `subsync-wrapper.sh` - SubSync execution and result handling.
- `Dockerfile` - runtime image.
- `docker-compose.yml` - standalone runtime.
- `.env.example` - configuration template.

## License

GPL-3.0. See `LICENSE`.
