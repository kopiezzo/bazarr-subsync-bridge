# Contributing

Keep changes small, operationally clear, and easy to roll back.

## Flow

1. Branch from the default branch.
2. Make one focused change.
3. Run the verification commands from `README.md`.
4. Open a pull request with the standard sections.

## Commit Style

Use lowercase `type/scope: summary`.

Examples:

- `fix/queue: handle empty job files`
- `docs/repo: modernize project metadata`
- `chore/runtime: refresh dependency pins`

## Pull Requests

Required sections:

- `## Summary`
- `## Verification`

Add when relevant:

- `## Risk and rollback`
- `## Notes`

## Ground Rules

- Do not commit credentials, `.env`, tokens, logs, or runtime state.
- Keep queue behavior stable unless the change explicitly targets it.
- Update docs when commands, env vars, mounts, or runtime flow change.
