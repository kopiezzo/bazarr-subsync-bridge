# Contributing

Keep changes focused, verifiable, and easy to review. Read the [README](README.md) before changing runtime behavior.

## Workflow

1. Branch from `main` and name the branch `type/topic`, for example `fix/queue-rescan` or `docs/configuration`.
2. Make one logical change. Update documentation in the same change when commands, environment variables, mounts, or runtime flow change.
3. Run the relevant checks from the [README](README.md#verification). Report the exact checks run and any checks you could not run.
4. Open a pull request using the [pull request template](.github/PULL_REQUEST_TEMPLATE.md). Keep only relevant sections and do not leave empty headings. Use a draft pull request if you need feedback before the work is ready.

Pull requests are squash-merged and the branch is deleted after merge. The pull request title becomes the commit subject, so it follows the commit format below.

## Commit format

```text
type(scope): summary

Body: why the change is needed, what was verified, and how to roll back
when relevant. Wrap at 72 characters.
```

- **Type:** `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, or `revert`.
- **Scope:** optional, lowercase, for example `queue`, `subsync`, `container`, `compose`, `build`, or `ci`.
- **Summary:** imperative mood, lowercase after the colon, no trailing period, and at most 72 characters for the whole subject line.
- **Breaking changes:** add `!` after the type or scope and a `BREAKING CHANGE:` footer that describes the impact and migration.

Example: `fix(queue): rescan after missed watcher events`.

## Releases

Releases use annotated semantic version tags (`v1.2.0`). The GitHub release has the same title and lists changes grouped as Features, Fixes, and Other.

## Safety

- Do not commit `.env`, credentials, Plex tokens, logs, queue payloads, or private media paths.
- Preserve queue validation, startup processing, subtitle backups, and opportunistic Plex refresh unless the change explicitly addresses them.
- Document observed behavior and test results accurately; do not claim a container or integration test passed if it was not run.
