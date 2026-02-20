# Bazarr SubSync Bridge

Queue-based subtitle synchronization service for Bazarr workflows, powered by [sc0ty/subsync](https://github.com/sc0ty/subsync).

## Features

- Watches a queue directory for JSON jobs produced by Bazarr post-processing.
- Runs `subsync` for each `video` and `subtitle` pair.
- Validates required job fields before processing.
- Optionally refreshes Plex sections after successful synchronization.
- Keeps logs and execution artifacts for operational diagnostics.

## Architecture

- `bazarr-postprocess.sh` - Bazarr hook that writes queue jobs.
- `subsync-monitor.sh` - queue watcher and job dispatcher.
- `subsync-wrapper.sh` - `subsync` execution and result handling.
- `docker-compose.yml` - service runtime mounts and environment.
- `Dockerfile` - container image with runtime dependencies.

## Quickstart

1. Clone this repository.
2. Copy environment template:

```bash
cp .env.example .env
```

3. Edit `.env` and set at least:
   - `MEDIA_HOST_PATH` (absolute host path to your media)
   - optional Plex variables if you use that integration
4. Start service:

```bash
docker compose up -d --build
```

5. Verify container is running:

```bash
docker compose ps
docker compose logs -f subsync
```

## Bazarr Integration

Use this command in Bazarr custom post-processing:

```text
/config/scripts/bazarr-postprocess.sh {{episode}} {{subtitles}} {{subtitles_language_code3}} {{episode_language_code3}}
```

### How to install `bazarr-postprocess.sh`

The script is included in this repository as `bazarr-postprocess.sh`.

For a Bazarr container/user:

1. Copy it into Bazarr scripts folder (example):

```bash
cp bazarr-postprocess.sh /config/scripts/bazarr-postprocess.sh
chmod +x /config/scripts/bazarr-postprocess.sh
```

2. Make sure Bazarr writes queue files to a path shared with `subsync`.
   - In Bazarr environment, set `SUBSYNC_QUEUE_DIR` (example: `/config/scripts/subsync-queue`).
   - In `subsync` service, mount the same host directory to `/queue`.

3. Make sure media paths from Bazarr (`{{episode}}`, `{{subtitles}}`) exist inside the `subsync` container too.
   - This is why `MEDIA_HOST_PATH` and `MEDIA_CONTAINER_PATH` must reflect your real mapping.

### Bazarr setup checklist

- [ ] `bazarr-postprocess.sh` exists in Bazarr scripts directory and is executable.
- [ ] Bazarr post-processing command is exactly:
  - `/config/scripts/bazarr-postprocess.sh {{episode}} {{subtitles}} {{subtitles_language_code3}} {{episode_language_code3}}`
- [ ] `SUBSYNC_QUEUE_DIR` points to a directory shared with the `subsync` container.
- [ ] The shared queue directory is mounted to `/queue` in `subsync`.
- [ ] Media paths from Bazarr are valid inside `subsync` (same path mapping semantics).
- [ ] A test subtitle download creates a `job-*.json` file and it disappears after processing.
- [ ] `docker compose logs -f subsync` shows a successful run (`OK SubSync completed successfully`).

## Queue Job Format

Each job is a JSON file in `/queue` with at least:

```json
{
  "video": "/media/shows/Show/Season 01/Episode.mkv",
  "subtitle": "/media/shows/Show/Season 01/Episode.pl.srt",
  "subtitle_lang": "pol",
  "video_lang": "eng"
}
```

Required keys: `video`, `subtitle`.

## Configuration

See `.env.example` for all variables.

Common knobs:

- `SUBSYNC_EFFORT`
- `SUBSYNC_MAX_WINDOW`
- `SUBSYNC_MIN_CORRELATION`
- `SUBSYNC_LOG_LEVEL`

Optional integrations:

- Plex: `PLEX_URL`, `PLEX_TOKEN`, `PLEX_SECTION_SHOWS`, `PLEX_SECTION_MOVIES`

## Troubleshooting

### Job processed but sync failed

- Check logs:
  - `docker compose logs -f subsync`
  - inspect `/logs/subsync-exec.log` inside mounted logs directory

### "File not found" in wrapper

- Your media mapping is inconsistent.
- Verify that path from Bazarr exists inside `subsync` container.

### No jobs are being picked up

- Check queue mount:
  - host queue path from `.env` must be mounted to `/queue`
- Confirm queue files end with `.json`.

### Plex refresh not triggered

- Missing or invalid `PLEX_URL` or `PLEX_TOKEN`.
- Sync itself still succeeds; Plex refresh is non-blocking.

## Security Notes

- Treat the queue directory as a trusted input boundary.
- Only Bazarr (or trusted automation) should be able to write `*.json` files to `/queue`.
- Do not commit `.env` files or share logs that include internal hostnames/URLs.

## Verification

Run local verification before publishing:

```bash
bash -n subsync-monitor.sh
bash -n subsync-wrapper.sh
bash -n bazarr-postprocess.sh
docker compose config
docker build -t bazarr-subsync-bridge .
```

## Repository Layout

- `bazarr-postprocess.sh`
- `subsync-monitor.sh`
- `subsync-wrapper.sh`
- `docker-compose.yml`
- `Dockerfile`
- `.env.example`

## Contribution Workflow

- commit subject: `type/scope: action object`
- PR sections: `## Summary`, `## Verification` (plus `## Risk and rollback` / `## Notes` when relevant)

## Included Docs

- `SECURITY.md`
- `CONTRIBUTING.md`
- `CODE_OF_CONDUCT.md`
- `LICENSE`
