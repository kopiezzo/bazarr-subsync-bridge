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
docker build -t subsync-container .
bash -n subsync-monitor.sh
bash -n subsync-wrapper.sh
```

## Pull request guidelines

- Explain why the change is needed.
- Describe how to verify it.
- Mention risk/watchouts when touching runtime behavior.

## Commit style

Use clear, imperative messages, for example:
- `add plex refresh timeout handling`
- `fix queue file validation for empty payloads`
