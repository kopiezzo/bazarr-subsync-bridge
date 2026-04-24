# AGENTS.md

Applies under `/home/lukasz/docker-builds/subsync`.

## Scope

- Single-container queue watcher running `subsync`.
- Shell scripts here are production runtime logic.

## Rules

- Runtime path is `supervisord` -> `subsync-monitor.sh` -> `subsync-wrapper.sh`.
- Keep `set -euo pipefail` style and explicit validation in shell scripts.
- Queue jobs require `video` and `subtitle`; do not weaken that contract silently.
- Existing `*.json` queue jobs must be processed on monitor startup before waiting for new inotify events.
- Processed queue files should still be drained to avoid reprocessing loops.
- Preserve subtitle backup behavior unless the task explicitly changes recovery expectations.
- Plex and Portal refreshes are opportunistic; failures should warn without breaking a successful subtitle sync.
- Key env groups: queue/log dirs, Plex settings, Portal settings, and `SUBSYNC_*` tuning vars.

## Verify

- `docker build -t subsync .`
- `docker run --rm -e QUEUE_DIR=/queue -v $(pwd)/queue:/queue -v $(pwd)/logs:/logs subsync`
- `bash ./subsync-wrapper.sh VIDEO SUBTITLE`

## Keep Updated

- If you change runtime flow, queue contract, env contract, logging behavior, or verification commands, update this file in the same task.
