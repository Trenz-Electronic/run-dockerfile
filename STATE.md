# STATE — rootless/macOS CI cell work (handoff)

Snapshot for continuing the **6-cell badge matrix** work, especially the two
remaining macOS Podman failures, directly on the self-hosted macOS runner.

## TL;DR

- **Linux is fully green** (Docker, Podman rootful, Podman rootless). The rootless
  cell passes honestly: `44 passed, 0 failed, 3 skipped` (the 3 skips are
  cross-arch qemu tests the rootless cell legitimately doesn't provide).
- **macOS Podman**: 4 of the 6 failures fixed (`0019 0022 0025 0038`); **2 remain
  to finish on the Mac**: `0017` (both rootful+rootless) and `0006` (rootless only).
- Everything below is pushed to `main` (HEAD around `a65c7da` + this file). Pull on
  the Mac to get it.

## Root causes already fixed (all on `main`)

| Area | Root cause | Fix (commit) |
|---|---|---|
| Linux rootless `0036` | podman `keep-id` reads `$USER`; a wrong/unset `$USER` (`0036` uses `env -u USER`) makes it build a broken id-map → `container uses ID mappings … but doesn't map UID 0` | `build-and-run` exports `USER=$(id -un)` in the rootless branch (`cc9f87d`) |
| Linux rootless `0019`,`0021` | `keep-id` pre-injects a passwd entry whose **home = the workdir**, so `su` lands the command in the wrong `$HOME` and `~`/`#copy.home:` files are invisible | `run-dockerfile-user-command` prepends `HOME=$HOME` to the exec (`1eeb051`) |
| Linux rootless `0029` | teardown `rm -rf` can't delete rootless podman's **sub-UID-owned** image store written under the test's isolated `$HOME` | `0029` cleanup runs `$ENGINE unshare rm -rf` first (`aed36ea`) |
| macOS `0019 0022 0025 0038` | macOS Podman VM shares `$HOME` and `/private/tmp` but **NOT the `/tmp` symlink**; literal `/tmp/...` bind sources fail with `statfs …: no such file or directory`. **Spaces were a red herring** (spaced `$HOME`/`/private/tmp` paths work). | resolve `/tmp`→`/private/tmp` via `pwd -P` for the `#copy.home:` archive (`build-and-run`) and in tests `0022`/`0038` (`a65c7da`) |

Also added: `build-and-run` prints the full assembled run command under
`RUN_DOCKERFILE_VERBOSE=1` (`run-dockerfile: exec: …`) — handy for these.

### How the Linux rootless cause was found (so you trust it)
Disproved `--platform`, bind mounts, and the baked image by **replaying the exact
commands build-and-run issues** — they passed. Wrapped `podman` to diff its
environment between the failing `tests/run 0036` and a passing manual replay; the
only meaningful difference was `USER=definitely_not_the_user` vs `USER=runner`.

## What's LEFT on macOS

Expected post-fix state (please confirm): **rootful** should fail only `0017`;
**rootless** should fail `0006` + `0017`.

### `0017_auto_rebuild` (both modes)
Fails at **Test 5 "Add context file (should trigger rebuild)"**. The error is
*hidden* because the test does `output=$(./run … 2>&1)` under dash `set -e`, so a
non-zero `./run` exits the script before printing. Reproduce directly to see it:

```sh
# from the run-dockerfile checkout on the Mac; RDF=<abs path to build-and-run>
RDF="$PWD/build-and-run"
cd /tmp && rm -rf p17 && mkdir p17 && cd p17
printf 'FROM alpine:latest\n' > Dockerfile
ln -sf "$RDF" run
RUN_DOCKERFILE_ENGINE=podman RUN_DOCKERFILE_VERBOSE=1 ./run echo hello      # first build  (Tests 1-4 analog)
echo "test content" > test_file.txt                                        # add a context file
RUN_DOCKERFILE_ENGINE=podman RUN_DOCKERFILE_VERBOSE=1 ./run echo "after context change"   # <-- Test 5: watch the error
echo "rc=$?"
# repeat with the rootful connection:
#   RUN_DOCKERFILE_ENGINE='podman --connection podman-machine-default-root'
```
Hypotheses to check: a `podman build`/rebuild failure specific to the macOS VM, or
the run failing after the context-hash rebuild. Test 4 (Dockerfile change → rebuild)
*passes*, so it's something about the context-file-triggered rebuild path.

### `0006_volume_mount_home` (rootless only)
Symptom (rootless): the container writes a marker into the bind-mounted `$HOME`,
then the host can't read it:
```
cat: can't open '/Users/andrei/.run-dockerfile-test-XXXX': Permission denied
FAIL: Could not read marker file from container
```
Rootful passes (VM root → virtiofs maps to the Mac user). Rootless likely maps the
container writer to a uid the Mac user can't read → genuine virtiofs+rootless
ownership limitation. Reproduce:
```sh
RDF="$PWD/build-and-run"
cd /tmp && rm -rf p06 && mkdir p06 && cd p06
printf '#mount: home\nFROM alpine:latest\n' > Dockerfile
ln -sf "$RDF" run
m="$HOME/.rdf-probe-0006"; rm -f "$m"
RUN_DOCKERFILE_ENGINE=podman ./run sh -c "echo HI > '$m'; ls -ln '$m'; id"   # inside-container view
ls -ln "$m"; cat "$m"; echo "host-read-rc=$?"                                # host view
rm -f "$m"
```
Compare the file's owner inside vs on the host. Decision to make: real fix (if the
write can be made host-readable) **or** honestly capability-gate `0006` on the
rootless-macOS cell (add a cap the rootless-macOS cell doesn't provide, tag `0006`)
— consistent with the honest-badge design.

There is also a dispatchable probe that captures both with full output:
`gh workflow run probe-macos.yml -f engine=podman` (rootless) /
`-f engine='podman --connection podman-machine-default-root'` (rootful).

## CI / runner gotcha (important)

**Every push to `main` triggers all 6 cell workflows**, and the single self-hosted
macOS runner serializes its 3 jobs per push — so several quick pushes pile up a long
backlog (this happened; I cancelled stale rounds). Mitigations to consider:
- a `concurrency: {group: …, cancel-in-progress: true}` on the caller workflows so a
  new push supersedes older queued runs (I add this in the same change as this file);
- or run the macOS checks manually in a terminal (commands above) instead of via CI.

To watch a cell's result:
```sh
gh run list --workflow="macOS · Podman (rootless)" --limit 1
JOB=$(gh api /repos/Trenz-Electronic/run-dockerfile/actions/runs/<RUNID>/jobs --jq '.jobs[0].id')
gh api /repos/Trenz-Electronic/run-dockerfile/actions/jobs/$JOB/logs   # `gh run view --log` is empty for reusable-workflow jobs
```

## Cleanup still pending (do before finishing)

- Delete the throwaway probe workflows: `.github/workflows/probe-rootless.yml` and
  `.github/workflows/probe-macos.yml` (keep the latter until `0017`/`0006` are done).
- Keep (recommended) the `RUN_DOCKERFILE_VERBOSE` run-command print — it's generally useful.
- Docs: add the rootless `$USER`+`HOME` notes and the macOS `/private/tmp` resolution
  to `CLAUDE.md`; the README badge table already has 6 cells. If `0006` is gated,
  document the cap and update the `tests/0006` entry.
- Delete this `STATE.md` once the work lands.

## Quick local emulation of each cell (Linux box)

```sh
# Linux · Podman rootless (the fixed flagship)
RUN_DOCKERFILE_ENGINE=podman RUN_DOCKERFILE_USERNS=keep-id \
  RUN_DOCKERFILE_CELL_CAPS='cgroups gnu-stat python3 linux rootless-podman' tests/run --all
```
(Note: rootless podman cannot run in a nested LXC container — that's why this whole
investigation went through CI rather than locally.)
