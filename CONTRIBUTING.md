# Contributing

Keep changes focused, verifiable, and easy to review. Read [`AGENTS.md`](AGENTS.md) before changing runtime behavior.

## Workflow

1. Branch from `main`. Use a short branch name such as `feat/<topic>`, `fix/<topic>`, or `docs/<topic>`.
2. Make one logical change and update documentation when commands, environment variables, mounts, or runtime flow change.
3. Run the relevant checks from the [README](README.md#verification). Report the exact checks run and any checks you could not run.
4. Open a pull request with a concise summary, verification, and impact or rollback details when relevant.

## Commits and pull requests

Use `type(scope): imperative summary` for commit and pull request titles, for example `fix(queue): handle empty job files`. The scope is optional. Common types are `feat`, `fix`, `docs`, `refactor`, `test`, `build`, `ci`, `chore`, `perf`, and `revert`. Keep the summary around 72 characters or less. Explain the reason or migration in the commit body when needed. Mark breaking changes with `!` and describe their impact.

Pull requests should normally contain one logical goal. Keep only relevant sections from the [pull request template](.github/PULL_REQUEST_TEMPLATE.md); do not leave empty headings. Use a draft pull request if feedback is needed before the work is ready. Work-in-progress commits can be squashed at merge; keep separate commits when they help explain the change.

## Safety

- Do not commit `.env`, credentials, Plex tokens, logs, queue payloads, or private media paths.
- Preserve queue validation, startup processing, subtitle backups, and opportunistic Plex refresh unless the change explicitly addresses them.
- Document observed behavior and test results accurately; do not claim a container or integration test passed if it was not run.
