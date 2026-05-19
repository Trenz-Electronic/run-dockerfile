# CLAUDE.md

## Project Overview

docker-booster is a single-script Docker workflow tool that automates image building, user mapping, and volume mounting for development environments.

## Design Principles

- **Follow user expectations**: Behavior should match what users intuitively expect. For example, relative paths in Dockerfile directives resolve from the Dockerfile's directory (not from `$PWD`), matching standard Dockerfile conventions like `COPY` and `ADD`.

## Key Files

- `build-and-run` - The main script (POSIX shell). This is the entire tool.
- `README.md` - User documentation. In the README.md, the focus is on what it does for users, including technical details only when necessary for using the docker-booster. The implementation details should go into CLAUDE.md.

## Dockerfile Directive Syntax

The script parses special comment directives from Dockerfiles:

| Directive | Location | Purpose |
|-----------|----------|---------|
| `# platform: <arch>` | First 10 lines | Cross-platform builds (arm64, amd64) |
| `#mount: .git pwd home` | First 20 lines | Control volume mounting with FIRST-found semantics |
| `#copy.home: <file>` | First 20 lines | Copy specific files from $HOME into container |
| `#usermount: <path>` | First 20 lines | Mount directories with env var expansion (creates if missing) |
| `#http.static: KEY=/path` | First 20 lines | Serve local dirs during build |
| `#option: <docker-args>` | First 20 lines | Pass additional args to `docker run` |
| `#sudo: all` | First 20 lines | Create sudoers entry for container user |

**Volume Mounting Control**:
- `#mount:` accepts keywords: `.git` (git repo root), `pwd` (current directory), `home` (home directory)
- FIRST-found semantics: checks keywords in order, uses first match
- Multiple `#mount:` directives accumulate keywords
- `#copy.home:` is purely run-time: on each `./run` invocation, build-and-run tars the listed files from host `$HOME`, bind-mounts the tarball at `/tmp/home-files.tar.gz`, and the in-container `user-command` extracts it into the new user's `$HOME` after user creation. If any file is missing on the host, the script exits 1 with an explicit error *before* `docker run` starts. The image itself never contains the host data.
- **Default behavior** (no `#mount:` directive): Try `.git` first, fall back to `pwd` (secure by default, no $HOME exposure)

**ENV Preservation**: `ENV` vars defined in the Dockerfile (after the last `FROM`) are automatically preserved across `su` inside the container.

**Privilege De-escalation**: The script uses `su` (not `sudo`) to drop privileges from root to the container user. This means containers do not need `sudo` installed. If `#sudo: all` is specified, a sudoers entry is created allowing passwordless sudo (requires sudo to be installed in the image).

## Architecture

The script operates in two modes based on `$0`:
1. **Normal mode** - Parses Dockerfile, builds image if needed, runs container
2. **user-command mode** - Runs inside container, creates user matching host UID/GID/group, executes command

User/group mapping preserves host username, UID, GID, and group name. If the group name already exists in the container with a different GID, it's renamed to `${groupname}_${gid}`.

The script automatically enables Docker BuildKit when Dockerfiles use `RUN --mount` syntax.

### Smart Rebuild Detection

The script implements hash-based rebuild detection:
- Calculates SHA-256 hash of all files in the build context (excluding `.git/`, `*.swp`)
- Stores hash as Docker image label: `docker-booster.context-hash`
- On subsequent runs, compares current hash with label from existing image
- Skips rebuild if hashes match, dramatically speeding up development workflow
- No external cache files needed - hash stored in Docker image metadata
- Single optimized `docker inspect` call retrieves architecture, creation time, and hash label

### Verbose Mode

The script is quiet by default, suppressing informational messages during normal operation. Set `DOCKER_BOOSTER_VERBOSE=1` in the environment to enable them.

- `DOCKER_BOOSTER_VERBOSE` environment variable controls verbosity (0=quiet, 1=verbose)
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

**Note:** Tests use a special structure (inside `tests/` directory) for testing purposes. The recommended user pattern is to place containers in a `containers/` directory at the project root, not inside the `docker-booster/` submodule. See README.md "Project Structure" section for details.

### Test Cases

- `0001_preserve_env` - Tests ENV vars from Dockerfile are preserved across sudo
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
- `0016_buildkit_auto` - Tests automatic BuildKit enablement for `RUN --mount` syntax
- `0017_auto_rebuild` - Tests hash-based automatic rebuild detection (skip rebuild when unchanged, detect Dockerfile and context changes)
- `0018_mount_directives` - Tests `#mount:` directive (pwd, .git, home, FIRST-found semantics)
- `0019_copy_home` - Tests `#copy.home:` directive (single file, multiple files, missing file error)
- `0020_sudo_directive` - Tests `#sudo: all` directive (su-based privilege drop, optional sudoers configuration)
- `0021_usermount_directive` - Tests `#usermount:` directive (directory creation, env var expansion, multiple paths)
