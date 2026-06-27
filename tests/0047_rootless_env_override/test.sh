#!/bin/sh
# Test: the RUN_DOCKERFILE_USERNS global rootless override env var.
#
# RUN_DOCKERFILE_USERNS=<mode> forces rootless Podman with --userns=<mode> across
# the whole run, without any Dockerfile directive - so a CI cell (or a user) can
# exercise the full suite rootless. A per-Dockerfile `#run-dockerfile: rootless`
# directive is more specific and wins; the value is validated; combining the
# override with a non-Podman RUN_DOCKERFILE_ENGINE is an error.
#
# Observed via RUN_DOCKERFILE_PRINT_ENGINE=1 (prints the engine on line 1, then
# "userns: <arg>" when rootless, then exits 0). A symlink-farm PATH exposes every
# host tool except docker/podman (stubbed), so no real daemon is contacted.

set -e

fail=0
WORK=$(mktemp -d)
BIN="$WORK/bin"
mkdir -p "$BIN"
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
make_stub docker
make_stub podman

# run_eng USERNS ENGINE -> sets global $out and $RC
run_eng() {
    if out=$(PATH="$BIN" RUN_DOCKERFILE_USERNS="$1" RUN_DOCKERFILE_ENGINE="$2" \
             RUN_DOCKERFILE_PRINT_ENGINE=1 ./run 2>&1); then
        RC=0
    else
        RC=1
    fi
}

# 1) env override alone -> bare podman (no sudo) + the userns arg
printf 'FROM alpine:latest\n' > Dockerfile
run_eng "keep-id" ""
line1=$(printf '%s\n' "$out" | sed -n '1p')
if [ "$RC" -eq 0 ] && [ "$line1" = "podman" ] && printf '%s\n' "$out" | grep -Fq 'userns: --userns=keep-id'; then
    echo "PASS: RUN_DOCKERFILE_USERNS -> podman (no sudo) + --userns=keep-id"
else
    echo "FAIL: env override resolution (rc=$RC): $out"; fail=1
fi

# 2) a per-Dockerfile directive is more specific and wins over the env
printf '#run-dockerfile: rootless --userns=keep-id:uid=1000\nFROM alpine:latest\n' > Dockerfile
run_eng "keep-id" ""
if [ "$RC" -eq 0 ] && printf '%s\n' "$out" | grep -Fq 'userns: --userns=keep-id:uid=1000'; then
    echo "PASS: Dockerfile directive wins over env override"
else
    echo "FAIL: directive precedence (rc=$RC): $out"; fail=1
fi

# 3) env override + RUN_DOCKERFILE_ENGINE=docker -> conflict error
printf 'FROM alpine:latest\n' > Dockerfile
run_eng "keep-id" "docker"
if [ "$RC" -ne 0 ] && printf '%s\n' "$out" | grep -Fiq podman; then
    echo "PASS: USERNS + engine=docker conflict rejected"
else
    echo "FAIL: USERNS + engine=docker not rejected (rc=$RC): $out"; fail=1
fi

# 4) invalid userns value rejected
printf 'FROM alpine:latest\n' > Dockerfile
run_eng "bad mode" ""
if [ "$RC" -ne 0 ] && printf '%s\n' "$out" | grep -Fq 'not a valid userns mode'; then
    echo "PASS: invalid RUN_DOCKERFILE_USERNS rejected"
else
    echo "FAIL: invalid userns not rejected (rc=$RC): $out"; fail=1
fi

# 5) unset override -> default resolution (rootful: sudo podman), not rootless
printf 'FROM alpine:latest\n' > Dockerfile
run_eng "" ""
if [ "$RC" -eq 0 ] && [ "$(printf '%s\n' "$out" | sed -n '1p')" = "sudo podman" ] \
   && ! printf '%s\n' "$out" | grep -Fq 'userns:'; then
    echo "PASS: unset override -> rootful default, no userns"
else
    echo "FAIL: unset override changed default (rc=$RC): $out"; fail=1
fi

rm -f Dockerfile
rm -rf "$WORK"
exit $fail
