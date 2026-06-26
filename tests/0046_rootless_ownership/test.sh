#!/bin/sh
# Test: rootless Podman with `#run-dockerfile: rootless --userns=keep-id` maps the
# in-container host-matching user to the host UID 1:1, so a file the user writes
# into a bind-mounted directory is owned by the HOST UID on the host - not a
# shifted subuid.
#
# This is the empirical "keep-id ownership" check. It requires a working rootless
# Podman and is SKIPPED (reported PASS) where that is unavailable - e.g. inside an
# unprivileged LXC container (no /dev/net/tun, nested-userns /proc mount denied),
# or where podman is not installed. It runs for real on CI (ubuntu-latest).

set -e

skip() { echo "SKIP: $1"; exit 0; }

command -v podman >/dev/null 2>&1 || skip "podman not installed"
command -v stat   >/dev/null 2>&1 || skip "GNU stat not available"

# Probe: can rootless Podman actually start a keep-id container here?
if ! podman run --rm --userns=keep-id alpine:latest true >/dev/null 2>&1; then
    skip "rootless podman cannot run keep-id containers in this environment"
fi

HOST_UID=$(id -u)
OUT=$(mktemp -d)
cleanup() { rm -rf "$OUT"; rm -f Dockerfile; }
trap cleanup EXIT

# The rootless directive forces bare `podman` (no sudo); -v mounts a host dir the
# in-container user will write into.
printf '#run-dockerfile: rootless --userns=keep-id\n#run-dockerfile: option -v %s:/mnt\nFROM alpine:latest\n' "$OUT" > Dockerfile

if ! env -u RUN_DOCKERFILE_ENGINE ./run sh -c 'touch /mnt/probe' >/dev/null 2>&1; then
    echo "FAIL: rootless keep-id run failed"
    exit 1
fi

OWNER=$(stat -c '%u' "$OUT/probe" 2>/dev/null || echo "?")
if [ "$OWNER" = "$HOST_UID" ]; then
    echo "PASS: keep-id bind-mount file owned by host UID $HOST_UID"
    exit 0
fi

echo "FAIL: keep-id bind-mount file owned by '$OWNER', expected host UID $HOST_UID"
exit 1
