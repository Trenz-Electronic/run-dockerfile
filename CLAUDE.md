@AGENTS.md
# CLAUDE.md

## Project Overview

run-dockerfile is a single-script container workflow tool that automates image building, user mapping, and volume mounting for development environments. It drives **Podman or Docker** — when both are installed Podman is preferred (rootful Podman as `sudo podman`); see the engine-resolution and rootless notes under Architecture.

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
- `tests/lib/engine.sh` - POSIX `/bin/sh` helper that resolves the container
  engine a test should use for its OWN image manipulation (fixtures, `rmi`,
  `inspect`), mirroring `build-and-run` so the test targets the same image store.
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
| `#run-dockerfile: rootless --userns=<mode>` | Anywhere | *(prefix-only)* | Force rootless Podman with the given user namespace |

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

The script always enables Docker BuildKit (`export DOCKER_BUILDKIT=1` before `docker build`) — the modern build path (the engine default since Docker 23.0) and a prerequisite for `RUN --mount`, cache mounts, build secrets, and named contexts. run-dockerfile assumes BuildKit is present and does not support the legacy builder; the override is forced on unconditionally, so a pre-set `DOCKER_BUILDKIT=0` in the environment is ignored. Podman ignores the unknown `DOCKER_BUILDKIT` env var, so the export is harmless under Podman.

### Container Engine Selection (Docker / Podman)

run-dockerfile drives **Docker or Podman**. The engine is never hardcoded: every `build`/`run`/`inspect` invocation expands the `ENGINE` bash array (`"${ENGINE[@]}"`), and `ENGINE_KIND` (`docker`|`podman`) gates the few per-engine differences. `resolve_engine()` runs after directive parsing:

- **Explicit override wins:** `RUN_DOCKERFILE_ENGINE` is taken verbatim and word-split into `ENGINE` (e.g. `docker`, `podman`, `sudo podman`, `sudo -n podman`); if its binary is not on `PATH` the run fails with a clear message.
- **Otherwise auto-detect:** both engines present defaults to **Podman**, exactly one present uses it, neither present is a hard error.
- **Rootful Podman ⇒ `sudo podman`.** Podman has no root daemon or `docker`-style group, so rootful access needs `sudo`. The script itself always runs as the **real host user** (so `id -un`/`id -u`/`id -g` keep detecting the correct identity for user mapping); only the engine invocations are elevated — there is no `SUDO_UID` juggling. A `RUN_DOCKERFILE_PRINT_ENGINE=1` diagnostic prints the resolved engine (and, when rootless, the `userns:` arg) and exits before any build/run, so you can confirm which engine will be used. Regression-tested by `tests/0044`.

Per-engine differences handled in the host driver:

- **`--progress=plain`** is a Docker/BuildKit flag (Podman `build` has no `--progress`); it is added only when `ENGINE_KIND = docker` (`PROGRESS_ARGS`).
- **Build output goes to stderr** (`"${BUILD_CMD[@]}" >&2`, likewise the derive build): Podman writes build progress and the image id to **stdout**, which would otherwise contaminate `$(./run cmd)` on a build-triggering invocation. Docker/BuildKit already writes to stderr, so this is a no-op there.
- **`#http.static:` host address is engine-aware:** Docker uses the `docker0` bridge gateway IP; Podman build containers are not on that bridge, so `HOST_IP="host.containers.internal"` (which Podman injects into build containers) is used instead. `--add-host=...:host-gateway` is deliberately **not** used — Buildah 1.28 rejects the `host-gateway` keyword.
- **Inherit-form env options are expanded host-side.** `expand_env_inherit()` rewrites `-e NAME` / `--env NAME` / `--env=NAME` (no `=value`) to `NAME=value` using the host environment before the run. The engine otherwise reads the value from its own environment, which `sudo podman` cannot see (sudo resets the environment), so a bare `-e NAME` would arrive empty. Behaviour-identical for Docker; an unset host `NAME` is left as the bare inherit form so it is still added to the preserve list and the container defines it empty (regression-tested by `tests/0037`).
- **macOS + Podman: the Dockerfile is fed to the build over stdin (`-f -`).** On macOS, `podman machine` serves the build context to the in-VM builder over a virtiofs share. An **atomic rename-replace of the Dockerfile on the host** — what editors do on save (vim, VSCode, …), and what `tests/0017` does to restore the Dockerfile after a change — leaves the VM's cached dentry for `Dockerfile` stale for a few seconds (a fixed ~5 s virtiofs cache window; re-reading the dir in the VM does not clear it sooner). A plain `podman build <ctx>` then fails with `Error: stat <ctx>/Dockerfile: no such file or directory` even though the file is present on the host. The host driver therefore sets `BUILD_DOCKERFILE_VIA_STDIN` when `ENGINE_KIND = podman` **and** `uname -s = Darwin`, appends `-f -` to `BUILD_CMD`, and runs the build with `< "$dir/Dockerfile"`. podman then never stats the stale entry; the rest of the context (COPY/ADD sources) still comes from the share and is read fresh. Scoped to macOS+Podman so Linux and Docker — which read the context directly, with no VM and no such cache — are byte-for-byte unaffected. The derived `*.user-command` bake is built from a fresh `mktemp` context (never renamed), so it needs no such treatment. Regression-tested by `tests/0017` (its Test 4 → Test 5 rename-then-rebuild is exactly this pattern, and failed on macOS Podman before the workaround).
- **macOS + Podman: the `#copy.home:` archive goes under the *real* temp dir.** The `podman machine` VM shares the host's `/private/tmp` and `$HOME` but **not** the `/tmp` symlink that points at `/private/tmp`, so a literal `/tmp/...` bind-mount source fails inside the VM with `statfs ...: no such file or directory`. `build-and-run` resolves `/tmp` with `pwd -P` (`_tmp_real`, `_tmp_real=$(cd /tmp && pwd -P)`) before placing the bind-mounted `#copy.home:` tarball — yielding `/private/tmp` on macOS (a shared path) and an unchanged `/tmp` on Linux (a no-op). The same spaces-are-a-red-herring `/tmp`→`/private/tmp` resolution is mirrored in tests `0022`/`0038`.

**Not handled — Podman short image names:** Podman (unlike Docker) does not assume `docker.io` for unqualified image names; it resolves only short-name aliases (`alpine`, `debian`, `ubuntu`, …) unless `unqualified-search-registries` is configured. run-dockerfile passes `FROM` lines through verbatim and deliberately does **not** rewrite them, so a Dockerfile with e.g. `FROM buildpack-deps:bookworm` fails under an unconfigured Podman. This is host configuration, not a run-dockerfile concern; it is documented in README.md, and the CI Podman job sets `unqualified-search-registries = ["docker.io"]` so the README-sample test (`tests/0029`, which uses `buildpack-deps`) resolves. (`tests/0029` therefore needs a Docker-Hub-resolving Podman; it passes under Docker and under a so-configured Podman.)

**Not handled — Dockerfile `COPY` here-documents under Podman:** the `COPY <<EOF … EOF` inline-file form is a Docker/BuildKit frontend feature. Podman/Buildah does not parse it (Buildah treats `<<EOF` as a literal source path and fails with `copier: stat "/<<EOF": no such file or directory`) — verified on both Buildah 1.28.2 and Podman 4.9.3 / Buildah 1.33 in CI, so this is a genuine engine-capability gap, not a version quirk to wait out. run-dockerfile passes the Dockerfile through verbatim, so a Dockerfile using `COPY <<EOF` builds only under Docker. The README's `installer-01-expect` sample uses this form and carries an engine note pointing Podman users at a sibling-file `COPY` instead; `tests/0029` sources `tests/lib/engine.sh` and **skips that one sub-sample under Podman** (the rest of the README samples are exercised under both engines).

**Not handled — `#mount: home` under rootless Podman on macOS:** the macOS `podman machine` VM shares `$HOME` over a virtiofs mount, and rootless Podman's default user namespace maps the host user to **container root**. A bind-mounted private (mode-700) `$HOME` therefore appears root-owned inside the container, and the unprivileged user the command runs as cannot even traverse it — every file under the mount yields `Permission denied`. There is no host-side fix that preserves run-dockerfile's privileged-setup model: `--userns=keep-id` maps the host user 1:1 (so the *user* could read `$HOME`) but then the root setup phase can no longer `chdir` into the 700 `$HOME` (container root becomes a subuid), and id-mapped (`:idmap`) bind mounts are rejected on virtiofs (`mount_setattr … Operation not permitted`). Rootful Podman (the VM root traverses everything) and Docker are unaffected. Rather than fail later on a confusing permission error, `build-and-run` detects this exact combination — the resolved mount dir equals `$HOME`, `ENGINE_KIND = podman`, `uname -s = Darwin`, and a positive `podman info … {{.Host.Security.Rootless}}` probe — and **exits early with an explanation** pointing at rootful Podman, Docker, `#copy.home:`, or `#usermount:`/`#mount: pwd`. Gated by the `home-bind` capability: every cell provides it except macos-podman-rootless, so `tests/0006` pre-skips there and runs (and passes) everywhere else.

**Rootless Podman** is opt-in via the `#run-dockerfile: rootless --userns=<mode>` directive. Docker and Podman keep **separate image stores** (`/var/lib/containers` vs `~/.local/share/containers` for rootless), so the first run under a newly selected engine rebuilds; the test runner and tests resolve the same engine (`tests/lib/engine.sh`) so fixtures and teardown target the matching store.

**`#run-dockerfile: rootless --userns=<mode>` directive:**
- **Prefix-only** — a brand-new directive, so it has **no** deprecated unprefixed (`#rootless:`) spelling. It is registered only in `build_directive_stream()`'s prefixed `known` list; an unprefixed `#rootless:` line is treated as a plain comment.
- The value is **mandatory** and must be a `--userns=<mode>` token (validated `^--userns=[A-Za-z0-9:=,._-]+$`); it is passed **verbatim** to `podman run`. Multiple `rootless` directives must agree on a single mode.
- Presence **forces rootless Podman**: `ENGINE=(podman)` with **no** sudo. It requires `podman` on `PATH` (else a hard error), and conflicts with a non-Podman `RUN_DOCKERFILE_ENGINE` (e.g. `docker`) — also a hard error.
- **Why rootless needs `--userns=keep-id`:** rootless Podman runs in a user namespace that remaps the container's UIDs through the invoking user's `subuid` range, so a non-root in-container process would write bind-mounted files owned by a shifted subuid (e.g. `100999`) rather than the host UID. `keep-id` pins the host UID 1:1, restoring run-dockerfile's core invariant (bind-mounted files owned by the host user). `keep-id` is the supported value; other modes (`host`, `nomap`, …) are accepted and passed through verbatim but reintroduce the ownership shift — see Podman's [`podman run --userns`](https://docs.podman.io/en/latest/markdown/podman-run.1.html#userns-mode) docs for their semantics. The `--userns` arg rides on `podman run` only (`ROOTLESS_RUN_ARGS`), not on `build` (rootless builds just use the rootless image store). Regression-tested by `tests/0045` (parsing/validation/conflict, stub-based) and `tests/0046` (keep-id host-UID ownership against a real rootless Podman; skips where rootless Podman is unavailable, e.g. inside an unprivileged LXC container).
- **keep-id consults `$USER`, so the rootless branch normalizes it.** Podman's `keep-id` reads `$USER` (not just `getuid()`) when it builds the in-container passwd entry and the userns id-map. A stale, empty, or deliberately wrong `$USER` (cron, `env -u USER`, a caller override) makes podman emit a one-entry mapping that omits UID 0, and the entry script's `podman run --user 0` start is then rejected with *"container uses ID mappings … but doesn't map UID 0"*. The rootless branch therefore `export`s `USER="$(id -un)"` so keep-id maps the host UID 1:1. The container user is still derived independently from `id -un`, so this only keeps the engine's own keep-id sane — it does not change the mapping run-dockerfile applies.
- **keep-id pre-injects a passwd entry whose home is the *workdir*, so the entry script forces `HOME`.** `su` would otherwise read `HOME` from that entry and land the command in the working directory rather than the host `$HOME`, hiding `~` and the extracted `#copy.home:` files. `run-dockerfile-user-command` prepends `HOME=$HOME` (the host home path it created, passed as the entry script's 5th argument) as a leading env assignment across the `su`, overriding whatever `su` derived — on every engine (a no-op when they already agree).

**Rootless is Podman-only for now.** Rootless *Docker* is unsupported: `--userns=keep-id` is a Podman/Buildah feature with no rootless-Docker equivalent — the first hurdle among several (a rootless-Docker path would need its own run-as-namespaced-root branch rather than reusing the Podman one). GitHub-hosted Ubuntu runners also ship **rootful** Docker only, so a CI lane would have to install rootless Docker per-run.

**Global rootless override — `RUN_DOCKERFILE_USERNS`:** an env var that forces rootless Podman with `--userns=<mode>` for the whole run **without** any Dockerfile directive, so a CI cell (or a user) can exercise an entire project rootless. Parsed right after the directive block, it only **seeds** `ROOTLESS_USERNS` when no `#run-dockerfile: rootless` directive is present (the per-Dockerfile directive is more specific and wins); `resolve_engine` then forces bare `podman`, and the same rules apply — a non-Podman `RUN_DOCKERFILE_ENGINE` is a hard error and the value is validated against the same `^--userns=<mode>$` regex. `tests/lib/engine.sh` and `tests/run` mirror the resolution (`RUN_DOCKERFILE_USERNS` set ⇒ bare `podman`) so test teardown targets the rootless store. Regression-tested by `tests/0047` (stub-based: override resolution, directive precedence, engine conflict, invalid value).

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
- `0006_volume_mount_home` - Tests `$HOME` is accessible inside container. Carries `# caps: home-bind`, so it runs on every cell except macos-podman-rootless (where a bind-mounted private `$HOME` is unreadable by the in-container user and build-and-run errors out early — see the `#mount: home` note under Container Engine Selection)
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
- `0029_readme_examples` - Tests indexed README Quick Start, command-line option, and Dockerfile directive samples by extracting them into a temporary project (including the "Non-interactive installers" `expect` sample, which is driven against a stand-in interactive `hello-installer.run` fixture so the heredoc `expect` script stays verified). Engine-aware: the `expect`/installer sub-sample uses a Dockerfile `COPY` here-document and is **skipped under Podman** (a Docker/BuildKit-only feature); all other samples run under both engines
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
- `0044_engine_selection` - Tests container-engine selection (`RUN_DOCKERFILE_ENGINE` override taken verbatim; auto-detect with both present defaulting to Podman, exactly one used, neither a hard error; rootful Podman ⇒ `sudo podman`) deterministically via a symlink-farm `PATH` and the `RUN_DOCKERFILE_PRINT_ENGINE` diagnostic — no real daemon
- `0045_rootless_directive` - Tests the `#run-dockerfile: rootless --userns=<mode>` directive (forces bare `podman` + verbatim userns arg; mandatory well-formed value; prefix-only; honored after line 20; conflict with `RUN_DOCKERFILE_ENGINE=docker` and missing-podman are hard errors) via stubs, no daemon
- `0046_rootless_ownership` - Integration test: under real rootless Podman with `--userns=keep-id`, a bind-mounted file written by the in-container host-matching user is owned by the **host UID** (not a subuid). Declares `# caps: rootless-podman` (runs only in the rootless-Podman cell) and self-skips via the shared `skip()` (exit 77) where rootless Podman cannot actually start (no podman, or an unprivileged LXC container)
- `0047_rootless_env_override` - Tests the `RUN_DOCKERFILE_USERNS` global rootless override (forces bare `podman` + `--userns=<mode>`; a `#run-dockerfile: rootless` directive still wins; conflict with `RUN_DOCKERFILE_ENGINE=docker` and an invalid mode are hard errors) via stubs, no daemon

### Capability tags and the engine/OS support matrix

Tests declare the capabilities they require with a `# caps: <tokens>` comment (scanned by `tests/run`'s `test_caps`); a CI **cell** declares the capabilities it provides via `RUN_DOCKERFILE_CELL_CAPS`. When that var is set, `tests/run` runs a test iff its required caps are a subset of the cell's, otherwise **pre-skips** it (reported), and **fails** the run if a test whose caps *are* provided self-skips anyway (exit 77) — so a green cell cannot hide a silently-skipped suite. With the var unset (local dev) nothing is pre-skipped and probe skips are tolerated, so behavior is unchanged.

- **SKIP sentinel:** `tests/lib/skip.sh` provides `skip()` → `echo "SKIP: ..."; exit 77`. `tests/run` treats exit `0` = PASS, `77` = SKIP, anything else = FAIL — exit-code, not output, because `0029` prints `SKIP:` lines yet exits 0. Reserve `skip()` for environment realities the caps cannot predict (e.g. rootless Podman that cannot start in a nested LXC); predictable gating belongs in `# caps:`.
- **Capability vocabulary:** `qemu-amd64`/`qemu-arm64`/`qemu-armv7` (a foreign-arch `#platform:` image runs here), `cgroups` (container cgroup limits observable), `python3` (host server for `#http.static`), `linux` (host-side Linux behavior, e.g. `/dev/pts`), `rootless-podman` (bare rootless Podman with global keep-id), `home-bind` (a bind-mounted private mode-700 `$HOME` is readable by the in-container host-matching user — **not** provided by macos-podman-rootless, where virtiofs + the rootless user namespace map the host user to container root; see the `#mount: home` note under Container Engine Selection), `gnu-stat` (reserved, no host-side use today). Only gated tests carry a tag: `0002 0003 0004` (qemu-*), `0006` (home-bind), `0008 0029 0030` (python3), `0010` (linux), `0011 0014` (cgroups), `0046` (rootless-podman); the rest are engine/OS-agnostic and run in every cell.
- **6-cell CI:** a reusable workflow `.github/workflows/cell.yml` (`workflow_call`, inputs `runner-json`/`engine`/`userns`/`cell-caps`/`setup-*`) runs `tests/run --all` once per cell; six thin caller workflows give one badge each — `linux-docker`, `linux-podman-rootful`, `linux-podman-rootless` (bare `podman` + `RUN_DOCKERFILE_USERNS=keep-id`), `macos-docker`, `macos-podman-rootful`, `macos-podman-rootless`. On macOS, Podman runs in a `podman machine` VM that exposes **both** a rootful connection (`podman-machine-default-root`, selected via `engine: 'podman --connection …'`) and the default rootless one, so each is its own cell; macOS `cell-caps` start conservative. The old single `test.yml` with its hand-maintained `grep -vE '^000[234]_|^0046_'` exclusion list is gone; cell membership is now derived from caps.
