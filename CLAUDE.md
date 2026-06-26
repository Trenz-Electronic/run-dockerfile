@AGENTS.md
# CLAUDE.md

## Project Overview

run-dockerfile is a single-script Docker workflow tool that automates image building, user mapping, and volume mounting for development environments.

## Design Principles

- **Follow user expectations**: Behavior should match what users intuitively expect. For example, relative paths in Dockerfile directives resolve from the Dockerfile's directory (not from `$PWD`), matching standard Dockerfile conventions like `COPY` and `ADD`.
- **Host portability**: `build-and-run` must run on the host's stock toolchain, not just GNU/Linux. It targets Linux **and** stock macOS (BSD userland, no GNU coreutils), so prefer POSIX-compatible invocations and provide portable fallbacks where GNU-only behavior is needed — e.g. `compute_context_hash()` uses a deterministic GNU `tar` stream when available and falls back to a portable metadata manifest otherwise, and the SHA-256 helper adapts to `sha256sum` vs `shasum`. The in-container entry point `run-dockerfile-user-command` carries the same constraint one level down: it must stay POSIX `sh` (busybox ash / dash), since the container shell is not guaranteed to be bash. When adding host-side logic, assume neither GNU coreutils nor bash-only externals are present unless you guard for them.

## Key Files

- `build-and-run` - The host driver (host **bash**, `#!/usr/bin/env bash`): parses the
  Dockerfile, builds the image, bakes in the entry script, and runs the container. This
  is the file symlinked as `run` beside a project Dockerfile.
- `run-dockerfile-user-command` - The in-container entry point (**POSIX sh**), baked by
  `build-and-run` into the image at `/bin/run-dockerfile-user-command`. Creates the
  host-matching user, drops privileges with `su`, and execs the command. Never runs on
  the host. See the two-file note under Architecture.
- `tests/lib/portable.sh` - POSIX `/bin/sh` helpers for test-only host portability
  checks. Product portability helpers belong in `build-and-run`.
- `README.md` - User documentation. In the README.md, the focus is on what it does for users, including technical details only when necessary for using the run-dockerfile. The implementation details should go into CLAUDE.md.

## Dockerfile Directive Syntax

The script parses special comment directives from Dockerfiles. The canonical form
is a `#run-dockerfile:` prefix (with `#` at column 1) followed by the directive
keyword and its value; prefixed directives may appear **anywhere** in the file.
The older unprefixed spellings are **deprecated**: honored only in the first 20
lines and reported with a one-time deprecation warning on stderr.

| Directive (canonical) | Location | Deprecated form | Purpose |
|-----------------------|----------|-----------------|---------|
| `#run-dockerfile: platform <arch>` | Anywhere | `# platform:` (first 20) | Cross-platform builds (arm64, amd64) |
| `#run-dockerfile: mount .git pwd home` | Anywhere | `#mount:` (first 20) | Control volume mounting with FIRST-found semantics |
| `#run-dockerfile: copy.home <file>` | Anywhere | `#copy.home:` (first 20) | Copy specific files from $HOME into container |
| `#run-dockerfile: usermount <path>` | Anywhere | `#usermount:` (first 20) | Mount directories with env var expansion (creates if missing) |
| `#run-dockerfile: http.static KEY=/path` | Anywhere | `#http.static:` (first 20) | Serve local dirs during build |
| `#run-dockerfile: context name=value` | Anywhere | `#context:` (first 20) | Pass BuildKit named contexts to `docker build` |
| `#run-dockerfile: option <docker-args>` | Anywhere | `#option:` (first 20) | Pass additional args to `docker run` |
| `#run-dockerfile: sudo all` | Anywhere | `#sudo:` (first 20) | Create sudoers entry for container user |

**Directive normalization**: `build_directive_stream()` (one awk pass, run before any directive parsing) rewrites both spellings into a single canonical `#<keyword>: <value>` stream in Dockerfile order, which every parser then consumes instead of re-reading the Dockerfile. Prefixed lines (`^#run-dockerfile:` at column 1) are honored anywhere; a prefixed line with no whitespace after the colon, an empty/missing keyword, or an unknown keyword is a hard error (the prefix signals intent, so it is reported, not ignored). Unprefixed known directives in the first 20 lines are emitted verbatim and collected for the deprecation warning. Order is preserved so `#platform:` (first match) and `#sudo:` (last match) keep their meaning. Regression-tested by `tests/0043`.

**Volume Mounting Control**:
- `#mount:` accepts keywords: `.git` (git repo root), `pwd` (current directory), `home` (home directory)
- FIRST-found semantics: checks keywords in order, uses first match
- Multiple `#mount:` directives accumulate keywords
- The **deprecated unprefixed** form is honored only in the first 20 lines; a known unprefixed directive after line 20 is an error rather than silently ignored (the error message points at the `#run-dockerfile:` prefix as the way to place it anywhere). Prefixed directives are honored at any line.
- `#copy.home:` is purely run-time: on each `./run` invocation, build-and-run tars the listed files from host `$HOME`, bind-mounts the tarball at `/tmp/home-files.tar.gz`, and the in-container `run-dockerfile-user-command` extracts it into the new user's `$HOME` after user creation. If any file is missing on the host, the script exits 1 with an explicit error *before* `docker run` starts. The image itself never contains the host data. Like `#usermount:`, it takes **exactly one path per directive line** (trimmed, parsed into a bash array), so filenames may contain spaces; use multiple `#copy.home:` lines for multiple files. After extraction, ownership is fixed **only** on the copied entries and the parent directories leading to them (driven by `tar tzf`, walking each member's ancestors) — never a recursive `chown -R` over `$HOME`, which could re-own a bind-mounted host home (`#mount: home`, or simply the project dir that usually lives under `$HOME`).
- `#usermount:` takes **exactly one path per directive line** (the whole value after the colon, trimmed), so paths may contain spaces. Use multiple `#usermount:` lines for multiple paths — they accumulate. (Unlike `#mount:`, which whitespace-splits its keywords, the value is *not* split into several entries.)
- `#context:` is build-time only and maps directly to Docker BuildKit named contexts: `#context: name=value` becomes `docker build --build-context name=value`. Multiple directives accumulate. The parser splits only on the first `=`, trims outer whitespace around the name and value, validates only the name (`[a-z_][a-z0-9_.-]*`), and passes the value through a bash array without shell evaluation. Local values resolve from the Dockerfile directory: absolute paths stay absolute; `./`, `../`, and bare relative paths are resolved against that directory and must exist before build. Values that look like URI/special forms (`scheme://...`, `target:...`, Git-style `user@host:path`) pass through unchanged. Named contexts require BuildKit, which run-dockerfile always enables (see below).
- `#option:` takes one Docker option per directive line. The parser strips the directive prefix, trims trailing whitespace, splits once at the first whitespace, and passes the first token plus the entire remaining text as two bash-array arguments. This keeps common forms like `#option: --cpus 1` backward compatible while allowing option values with spaces, e.g. `#option: -v /tmp/my cache:/cache` and `#option: -e FLAGS=--mode fast`. Boolean flags such as `#option: --read-only` are single-token directives; adding a value to a known boolean flag is rejected.
- **Default behavior** (no `#mount:` directive): Try `.git` first, fall back to `pwd` (no default $HOME exposure)

**ENV Preservation**: `ENV` vars defined in the Dockerfile (after the last `FROM`) are automatically preserved across `su` inside the container. Both the `ENV k=v [k2=v2 ...]` form (**every** name on the line is preserved, parsed one-name-per-field by `awk`) and the legacy `ENV key value` form are handled; an `=` inside a value stays within its field and is not mistaken for another name. Two parsing limitations are intentional: quoted values containing whitespace are only best-effort, and line-continuations (`\` at end of line) are not joined — put such a variable on its own `ENV` line if its preservation matters. On the container side the preserved list is dereferenced via `eval`, but each name is re-validated against `^[A-Za-z_][A-Za-z0-9_]*$` at that sink first, so a crafted command-line `-e 'name;cmd=val'` is skipped rather than executed (regression-tested by `tests/0031` and `tests/0035`).

**No shell expansion in directive values**: `#option:`, `#mount:`, `#copy.home:`, `#context:`, etc. are parsed with `grep`/`sed`, not evaluated by a shell, so values like `-e DISPLAY=$DISPLAY` are passed literally. To forward a host env var, use `-e VARNAME` (no `=value`) so docker inherits the value from the docker client's environment. The exception is `#usermount:`, which expands environment-variable references in its paths. This is done safely, **not** via `eval`: `expand_usermount_path()` only substitutes well-formed `$NAME`/`${NAME}` references with their value from `printenv`, so any env var works (`$HOME`, `$PWD`, `$VITIS_ROOT`, ...), while command substitution (`$(...)`/backticks), arithmetic, and positional parameters can never match the variable-name pattern and are left literal. References are resolved longest-first so a shared prefix (e.g. `$HOME` vs `$HOMEPAGE`) does not corrupt the longer name. Regression-tested by `tests/0021` (the command-substitution case must not execute on the host).

**Privilege De-escalation**: The script uses `su` (not `sudo`) to drop privileges from root to the container user. This means containers do not need `sudo` installed. If `#sudo: all` is specified, setup first verifies that `sudo` is installed, creates `/etc/sudoers.d` if needed, and writes a `0440` sudoers entry allowing passwordless sudo.

## Architecture

run-dockerfile is split into two files, each running under its own shell:

1. **Host driver — `build-and-run`, host `bash`.** Parses the Dockerfile and its
   directives, builds the base image if needed, bakes the in-container entry script into
   a thin derived image, and runs the container. It builds the `docker build` / `docker
   run` invocations as **bash arrays** expanded with `"${arr[@]}"` (e.g.
   `CMDLINE_DOCKER_ARGS`, `USERMOUNT_VARGS`, `DOCKER_OPTIONS`, `BUILD_CMD`, `DERIVE_CMD`),
   so paths and values containing spaces or glob characters are passed verbatim and **no
   `eval`** is used for the run/build commands. To locate the entry script for baking it
   follows `$0`'s symlinks to the real `build-and-run` and reads the sibling
   `run-dockerfile-user-command` (whereas `real_self`, used for the container dir/tag,
   deliberately leaves the `run` symlink **unresolved**).
2. **In-container entry point — `run-dockerfile-user-command`, container `/bin/sh`.**
   Baked into the image at `/bin/run-dockerfile-user-command` (the container is started
   with `--entrypoint /bin/sh ... /bin/run-dockerfile-user-command USER UID GID GROUP HOME
   CMD...`). It creates a user/group matching the host UID/GID, optionally writes a
   `#sudo: all` sudoers entry, extracts `#copy.home:` files, then drops privileges with
   `su` and execs the user's command. This file **must stay POSIX sh** (busybox ash /
   dash) — it never runs under bash. Preserved env vars are carried across the `su`
   privilege drop as positional parameters (`set -- "$var=$val" "$@"`), so values
   containing spaces survive intact.

User/group mapping preserves host username, UID, and GID. Group-name preservation is best-effort: if the host group name already exists in the container with a different GID, run-dockerfile creates `${groupname}_${gid}`; if that fallback name also exists with a different GID, it tries `${groupname}_${gid}_a` through `${groupname}_${gid}_z` before failing clearly. If another image group already has the host GID, both group names may share that numeric GID, and reverse lookups such as `id -gn` may report the image's first matching group name. The host user is mapped by **identity, not just name**: the image's existing user is reused only when it matches the host on name, UID *and* primary GID; if the image ships a user with the same name but a different UID/GID, the container instead runs as a distinct user `${username}_${uid}` carrying the host UID/GID (so bind-mounted files stay accessible). If that fallback username also exists with a different UID/GID, run-dockerfile tries `${username}_${uid}_a` through `${username}_${uid}_z` before failing. The `su` target and any `#sudo:` sudoers entry use this resolved user.

The host driver **bakes the in-container entry script** (`run-dockerfile-user-command`) into the image at `/bin/run-dockerfile-user-command` rather than bind-mounting it there at run time. After the base image is built (or found unchanged), a thin derived image `${tag}.user-command` is built `FROM` it with a single `COPY --chmod=0755 run-dockerfile-user-command /bin/run-dockerfile-user-command`; the container then runs from that derived image. The container starts as root before dropping to the mapped user, and the baked copy is a root-owned `0755` file, so a (compromised) container cannot overwrite it — and the host scripts are never exposed to the container at all (regression-tested by `tests/0032`). Baking adds no entry to the container's `/proc/mounts`, unlike a bind mount: a read-only real-filesystem mount is rejected by tools that enumerate mounts for a writability/disk-space check (e.g. RPM-based rootfs builds). The derived image carries a `run-dockerfile.user-command-hash` label binding the base image id and the entry-script content, so it is rebuilt only when either changes; the unchanged path costs one extra `docker inspect` and no build. The image tag is the container **directory name**, so it is validated up front against `^[a-z0-9][a-z0-9._-]*$`; an invalid name (e.g. containing uppercase) fails with an actionable message instead of a cryptic `docker build` "repository name must be lowercase" error (regression-tested by `tests/0033`).

`#http.static:` starts one throwaway Python HTTP server **per directive**, each on its own random port published to the build as `HTTP_<KEY>=<url>`. Each server writes its port to a **distinct** temp file (`/tmp/run-dockerfile-http-port-$$-<n>.txt`) so a second directive never reads a previous server's stale port; the host side waits up to 30 seconds for each port file before failing. The shared server script and all port files are removed by `cleanup_http_servers`, which is armed via an `EXIT`/`INT`/`TERM` trap before any server starts (regression-tested by `tests/0030`).

The script always enables Docker BuildKit (`export DOCKER_BUILDKIT=1` before `docker build`) — the modern build path (the engine default since Docker 23.0) and a prerequisite for `RUN --mount`, cache mounts, build secrets, and named contexts. run-dockerfile assumes BuildKit is present and does not support the legacy builder; the override is forced on unconditionally, so a pre-set `DOCKER_BUILDKIT=0` in the environment is ignored.

### Smart Rebuild Detection

The script implements hash-based rebuild detection:
- Calculates a SHA-256 hash of the build context (excluding `.git/`, `*.swp`) via `compute_context_hash()`
- Preferred path uses a **deterministic GNU `tar` stream** (`--sort=name --mtime=... --owner=0 --group=0 --numeric-owner`) piped to the host SHA-256 helper. Hashing the archive (not just concatenated content) folds each entry's **path, mode, and symlink target** into the fingerprint, so a rename or `chmod` that changes the built image triggers a rebuild; `mtime`/owner are normalized so unrelated metadata churn does not.
- Falls back to a portable metadata manifest when GNU `tar` is unavailable (e.g. stock macOS). The manifest sorts context entries and hashes each entry's path, type, mode, and either file-content digest or symlink target, so pure renames, chmod changes, and symlink retargets are still detected.
- Stores hash as Docker image label: `run-dockerfile.context-hash`
- On subsequent runs, compares current hash with label from existing image
- Named-context contents referenced by `#context:` are not included in this hash. The directive line itself remains in the Dockerfile/main-context hash, so changing `#context:` values triggers rebuilds, but changing only files inside a named context requires `docker rmi <image-name>` or another forced rebuild.
- Skips rebuild if hashes match, dramatically speeding up development workflow
- No external cache files needed - hash stored in Docker image metadata
- Single optimized `docker inspect` call retrieves architecture and the context-hash label

**Design note — the hash is deliberately conservative:** It fingerprints the whole build context, including the Dockerfile and the run-time-only directives in it (`#mount:`, `#copy.home:`, `#usermount:`, `#option:`, `#sudo:`). Editing one of those directives therefore triggers a rebuild even though it does not affect the built image. It also does **not** parse `.dockerignore`, so a change to an ignored file can trigger a rebuild Docker itself would skip. Both are intentional over-hashing and should not be "optimized" away:
- The spurious rebuild is nearly free. Docker strips comment lines during parsing, so they never participate in any layer's cache key; the forced `docker build` hits cache on every layer and finishes in ~1s. The only real waste is build-phase wrapper work (notably `#http.static:` server startup).
- The failure modes are asymmetric. Over-hashing (a line that did not need to trigger a rebuild) costs a cheap rebuild; under-hashing (excluding a line that *does* affect the build) yields a stale image and silently wrong behavior. Hashing everything keeps the safe default and makes the hash obviously correct.
- Filtering would couple the hash to the directive grammar, forcing every new directive to be re-classified as build-affecting or run-time. If spurious rebuilds ever become a real pain point, the cheaper fix is to skip the build-phase wrapper work on an all-cache-hit build, not to teach the integrity hash about directive semantics.

### Verbose Mode

The script is quiet by default, suppressing informational messages during normal operation. Set `RUN_DOCKERFILE_VERBOSE=1` in the environment to enable them; only the literal value `1` is treated as enabled.

- `RUN_DOCKERFILE_VERBOSE` environment variable controls verbosity (0=quiet, 1=verbose; other values are quiet)
- `info()` helper function outputs to stderr only when verbose mode is enabled
- Messages suppressed by default (runtime info):
  - Mount directive resolution ("Mount directive: Using home/pwd/git directory...")
  - Home file collection ("Collected home files for container...")
  - User mount listing ("Mounting user directories...")
- Messages always shown (build-phase and errors):
  - Image rebuild notifications
  - Platform/BuildKit detection
  - HTTP server start/stop
  - Build command execution
  - All ERROR/WARNING messages

## Testing

Run tests:
```sh
tests/run --all                    # Run all tests
tests/run 0001                     # Run single test by prefix
tests/run 0001 0003                # Run multiple tests
tests/run --no-cleanup --all       # Run all, keep containers for debugging
tests/run --cleanup                # Only cleanup, no tests
```

### Test Structure

Tests live in `tests/NNNN_name/` directories (numbered for ordering):
- `Dockerfile` - Test container definition (may be generated dynamically by test.sh)
- `run` - Symlink to `../../build-and-run`
- `test.sh` - Test script (exit 0 = pass, non-zero = fail)

**Note:** Tests use a special structure (inside `tests/` directory) for testing purposes. The recommended user pattern is to place containers in a `containers/` directory at the project root, not inside the `run-dockerfile/` submodule. See README.md "Project Structure" section for details.

### Test Cases

- `0001_preserve_env` - Tests ENV vars from Dockerfile are preserved across the internal `su` drop
- `0002_pragma_platform_aarch64` - Tests `# platform: arm64` runs container on aarch64
- `0003_pragma_platform_amd64` - Tests `# platform: amd64` runs container on x86_64
- `0004_pragma_platform_armv7` - Tests `# platform: arm/v7` runs container on armv7l (Zynq, RPi)
- `0005_user_mapping` - Tests container user matches host UID/GID
- `0006_volume_mount_home` - Tests `$HOME` is accessible inside container
- `0007_volume_mount_pwd` - Tests `$PWD` is accessible inside container
- `0008_pragma_http_static` - Tests `#http.static:` serves files during build
- `0009_tty_absent` - Tests no TTY when run without interactive terminal
- `0010_tty_present` - Tests TTY detected when run with pseudo-terminal
- `0011_pragma_option` - Tests `#option:` passes args to docker run
- `0012_cmdline_env` - Tests `-e` command-line option passes env vars
- `0013_pragma_option_env` - Tests `#option: -e` passes env vars
- `0014_cmdline_options` - Tests common docker options (-v, --network, --cpus)
- `0015_user_mapping_conflict` - Tests group name conflict handling (rename with GID suffix)
- `0016_buildkit_auto` - Tests BuildKit is enabled by default (a `RUN --mount` Dockerfile builds without any opt-in)
- `0017_auto_rebuild` - Tests hash-based automatic rebuild detection (skip rebuild when unchanged, detect Dockerfile and context changes, and detect file renames, mode changes, and fallback metadata changes)
- `0018_mount_directives` - Tests `#mount:` directive (pwd, .git, home, FIRST-found semantics)
- `0019_copy_home` - Tests `#copy.home:` directive (single file, multiple files, missing file error)
- `0020_sudo_directive` - Tests `#sudo: all` directive (su-based privilege drop, optional sudoers configuration)
- `0021_usermount_directive` - Tests `#usermount:` directive (directory creation, env var expansion, multiple directives, paths with spaces, command-substitution safety)
- `0022_space_in_path` - Tests a host bind-mount path containing a space is passed to docker verbatim (bash-array quoting)
- `0023_glob_in_option` - Tests a glob character in an `#option:` value is passed literally, not expanded against the host filesystem
- `0024_env_value_with_space` - Tests an env value with a space survives end-to-end through both shells (host array + container-side `set --` across `su`)
- `0025_copy_home_chown_scope` - Tests `#copy.home:` ownership fix is scoped to copied entries (a root-owned decoy in `$HOME` keeps its ownership; no recursive `chown -R`)
- `0026_user_mapping_uid_conflict` - Tests an image user with the host's username but a different UID is not reused; container runs with the host UID/GID
- `0027_context_directive` - Tests `#context:` named contexts (local path with spaces, no auto-rebuild on named-context-only changes, forced rebuild, missing path error, pass-through image context, invalid name)
- `0028_directive_location` - Tests known run-dockerfile directives after line 20 fail with a clear error instead of being silently ignored
- `0029_readme_examples` - Tests indexed README Quick Start, command-line option, and Dockerfile directive samples by extracting them into a temporary project (including the "Non-interactive installers" `expect` sample, which is driven against a stand-in interactive `hello-installer.run` fixture so the heredoc `expect` script stays verified)
- `0030_http_static_multiple` - Tests two `#http.static:` directives each serve their own directory (per-server port files, no stale-port mismap) and leave no port files behind
- `0031_env_multi_var` - Tests every variable on a multi-variable `ENV` line is carried into `DOCKER_PRESERVE_ENV`, not just the first
- `0032_user_command_readonly` - Tests `/bin/run-dockerfile-user-command` is baked into the image (root-owned, executable) and is NOT a bind mount (checked via `/proc/self/mountinfo` and `stat`), so the host script is never mounted in read-only
- `0033_invalid_image_name` - Tests a container directory name that is not a valid Docker image name fails early with a clear message
- `0034_verbose_nonnumeric` - Tests a non-numeric `RUN_DOCKERFILE_VERBOSE` value does not make `info()` emit a shell "integer expression expected" error
- `0035_env_name_injection` - Tests a command-line `-e` whose variable name embeds shell metacharacters is rejected at the container-side `eval` sink, not executed
- `0036_unset_user_env` - Tests the host username is resolved from `id -un` (not the `$USER` env var), so the user is mapped correctly when `$USER` is unset and a stale `$USER` does not leak into the mapping
- `0037_option_inherit_env` - Tests the inherit form `#option: -e VAR` (no `=value`) is added to the ENV-preserve list like the command-line `-e VAR`; the decisive check is a variable unset on the host becoming defined inside the container
- `0038_option_value_spaces` - Tests `#option:` values containing spaces for `-e`, `-v`, and `--mount`
- `0039_user_group_fallback_collision` - Tests fallback user/group names retry with `_a` when `${name}_${id}` already exists with the wrong numeric identity
- `0040_no_command` - Tests bare `./run` fails before container startup without exposing internal `user-command` usage
- `0041_missing_option_value` - Tests split-form docker run options fail clearly when their required value is missing
- `0042_help_usage` - Tests host-side `--help`/usage exits successfully without requiring Docker
- `0043_directive_prefix` - Tests the `#run-dockerfile:` directive prefix (honored anywhere incl. after line 20, whitespace required after the colon, `#` must be column 1, unknown keyword is a hard error, the deprecated unprefixed form still works and emits a deprecation warning, old and new forms accumulate)
