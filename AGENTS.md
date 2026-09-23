# AGENTS.md

Applies to this repository in any checkout. The repository is the source of truth for its scripts and container configuration.

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
- Plex refresh is opportunistic; failures should warn without breaking a successful subtitle sync.
- Key env groups: queue/log dirs, Plex settings, and `SUBSYNC_*` tuning vars.

## Verify

Run only checks relevant to the change and report what was actually verified.

- `bash -n bazarr-postprocess.sh subsync-monitor.sh subsync-wrapper.sh`
- `docker compose config --quiet`
- `docker build -t bazarr-subsync-bridge .`
- Use the Bazarr integration check in `README.md` when the service is available.

## Keep Updated

- If you change runtime flow, queue contract, env contract, logging behavior, or verification commands, update this file in the same task.
