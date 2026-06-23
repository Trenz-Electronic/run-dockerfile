# Repository Guidelines

## Project Structure & Module Organization

`run-dockerfile` is intentionally small. The main product is the Bash script
[`build-and-run`](build-and-run), which is normally symlinked as `run` beside a
project Dockerfile. User-facing documentation lives in [`README.md`](README.md);
implementation notes and architectural constraints live in [`CLAUDE.md`](CLAUDE.md).
Tests are integration-style shell tests in `tests/NNNN_name/`, with shared
portable helpers in `tests/lib/portable.sh`. GitHub Actions workflows are in
`.github/workflows/`.

## Build, Test, and Development Commands

There is no separate build step; edit `build-and-run` directly.

- `tests/run --all` - run the full Docker-backed test suite.
- `tests/run 0001` - run one test by numeric prefix.
- `tests/run 0001 0003` - run selected tests.
- `tests/run --no-cleanup --all` - keep test containers/images for debugging.
- `tests/run --cleanup` - remove test containers/images without running tests.

Most tests require a working Docker installation. Cross-architecture tests also
depend on Docker/QEMU platform support.

## Coding Style & Naming Conventions

Keep host-side code in `build-and-run` compatible with Bash and pass command
arguments through arrays rather than shell evaluation. The `user-command` branch
is executed by container `/bin/sh`; keep that branch POSIX-sh compatible. Use
clear lowercase function names with underscores, quote variable expansions, and
prefer explicit error messages. Tests are POSIX `sh` scripts with `set -e`.
Name new tests as `tests/NNNN_short_description/` and include `test.sh`; add a
`Dockerfile` only when the scenario needs one.

## Testing Guidelines

Add or update a focused numbered test for every behavior change or regression.
Prefer assertions that inspect externally visible behavior, not implementation
details. Use `tests/run <prefix>` while iterating, then `tests/run --all` before
opening a pull request. Update README examples when behavior or supported options
change; `tests/0029_readme_examples` validates documented samples.

## Commit & Pull Request Guidelines

Use concise, imperative subjects that describe the observable effect and read
well in `git log --oneline`. Prefix only when real and useful, such as
`README:`, `CI:`, `fix:`, or a known ticket ID; do not invent IDs or scopes. Add
a body only for reviewer-relevant context the subject cannot carry. Mention
rationale or verification only when supported or actually performed.

Pull requests should summarize problem and solution, list exact test commands,
note Docker platform limitations, link issues, and include docs for user-visible
changes.

## Security & Configuration Tips

Treat Dockerfile directives as data, not shell code. Avoid `eval`; preserve
quoting for paths, spaces, globs, and environment values. Be conservative with
mounting `$HOME`; prefer scoped directives such as `#copy.home:` or
`#usermount:` when documenting examples.
