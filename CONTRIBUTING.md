# Contributing

Thanks for helping improve this project.

## Before you start

- Open an issue first for larger changes.
- Keep changes focused and avoid unrelated refactors.

## Development flow

1. Fork or branch from `main`.
2. Make small, reviewable commits.
3. Validate changes locally.

Recommended checks:

```bash
docker build -t bazarr-subsync-bridge .
bash -n subsync-monitor.sh
bash -n subsync-wrapper.sh
```

## Pull request guidelines

- Use required sections:
  - `## Summary`
  - `## Verification`
- Add when relevant:
  - `## Risk and rollback`
  - `## Notes`

## Commit style

Use this format:

- `type/scope: action object`

Examples:

- `fix/automation: handle plex refresh timeout`
- `feat/queue: add payload validation for empty job files`
