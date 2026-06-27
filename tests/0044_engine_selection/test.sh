#!/bin/sh
# Test: container-engine selection.
#
# Resolution order (see CLAUDE.md): an explicit RUN_DOCKERFILE_ENGINE wins;
# otherwise auto-detect — both engines present defaults to Podman, exactly one
# present uses it, neither present is a hard error. Rootful Podman resolves to
# "sudo podman".
#
# Observed via RUN_DOCKERFILE_PRINT_ENGINE=1, which resolves the engine, prints
# it (space-joined) to stdout and exits 0 before any build/run. Engine presence
# is controlled deterministically with a symlink-farm PATH that exposes every
# host tool EXCEPT docker/podman, so `command -v` reflects only the stubs we add
# — no real daemon is contacted.

set -e

fail=0
WORK=$(mktemp -d)
BIN="$WORK/bin"
mkdir -p "$BIN"

# Mirror every host executable except docker/podman into a clean bin dir.
for d in /bin /usr/bin /usr/sbin /sbin; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
        [ -e "$f" ] || continue
        name=$(basename "$f")
        case "$name" in docker|podman) continue ;; esac
        [ -e "$BIN/$name" ] || ln -s "$f" "$BIN/$name" 2>/dev/null || true
    done
done

make_stub() { printf '#!/bin/sh\nexit 0\n' > "$BIN/$1"; chmod +x "$BIN/$1"; }

# A Dockerfile is present so build-and-run reaches engine resolution normally.
printf 'FROM alpine:latest\n' > Dockerfile

# check DESC  OVERRIDE  EXPECTED|FAIL  [present-engine ...]
check() {
    desc="$1"; override="$2"; expected="$3"; shift 3
    rm -f "$BIN/docker" "$BIN/podman"
    for e in "$@"; do make_stub "$e"; done
    # Clear any ambient RUN_DOCKERFILE_USERNS (e.g. the rootless CI cell sets it
    # job-wide) so it cannot override the engine resolution this test pins.
    if out=$(PATH="$BIN" RUN_DOCKERFILE_USERNS= RUN_DOCKERFILE_ENGINE="$override" RUN_DOCKERFILE_PRINT_ENGINE=1 ./run 2>&1); then
        rc=0
    else
        rc=1
    fi
    if [ "$expected" = "FAIL" ]; then
        if [ "$rc" -ne 0 ]; then
            echo "PASS: $desc (rejected)"
        else
            echo "FAIL: $desc — expected failure, got '$out'"; fail=1
        fi
    else
        if [ "$rc" -eq 0 ] && [ "$out" = "$expected" ]; then
            echo "PASS: $desc -> $out"
        else
            echo "FAIL: $desc — expected '$expected', got (rc=$rc) '$out'"; fail=1
        fi
    fi
}

# Auto-detect (no override)
check "both present -> sudo podman"   ""  "sudo podman"  docker podman
check "only docker -> docker"         ""  "docker"       docker
check "only podman -> sudo podman"    ""  "sudo podman"  podman
check "neither present -> failure"    ""  "FAIL"

# Explicit override wins and is taken verbatim
check "override docker beats podman default" "docker"      "docker"       docker podman
check "override bare podman (no sudo added)" "podman"      "podman"       docker podman
check "override sudo podman"                 "sudo podman" "sudo podman"  docker podman
check "override unknown binary -> failure"   "no-such-engine-binary" "FAIL" docker podman

rm -f Dockerfile
rm -rf "$WORK"
exit $fail
