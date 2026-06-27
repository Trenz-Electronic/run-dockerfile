#!/bin/sh
# Test: the `#run-dockerfile: rootless --userns=<mode>` directive.
#
# Presence forces rootless Podman: engine "podman" (NO sudo) plus the verbatim
# --userns=<mode> argument on the container run. The directive is prefix-only
# (no deprecated unprefixed spelling), its value is mandatory and must be a
# --userns=<mode> token, and it conflicts with a non-Podman RUN_DOCKERFILE_ENGINE.
#
# Observed via RUN_DOCKERFILE_PRINT_ENGINE=1, which prints the resolved engine on
# line 1 and, when rootless is active, "userns: <arg>" on line 2, then exits 0.
# Engine presence is controlled with a symlink-farm PATH exposing every host tool
# except docker/podman, so no real daemon is contacted.

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

run_engine() { # OVERRIDE -> stdout+stderr, sets global RC
    # Clear any ambient RUN_DOCKERFILE_USERNS (e.g. the rootless CI cell sets it
    # job-wide) so it cannot override the engine resolution under test.
    if out=$(PATH="$BIN" RUN_DOCKERFILE_USERNS= RUN_DOCKERFILE_ENGINE="$1" RUN_DOCKERFILE_PRINT_ENGINE=1 ./run 2>&1); then
        RC=0
    else
        RC=1
    fi
}

# 1) prefixed rootless directive -> engine podman (no sudo) + userns arg
printf '#run-dockerfile: rootless --userns=keep-id\nFROM alpine:latest\n' > Dockerfile
run_engine ""
line1=$(printf '%s\n' "$out" | sed -n '1p')
if [ "$RC" -eq 0 ] && [ "$line1" = "podman" ] && printf '%s\n' "$out" | grep -Fq 'userns: --userns=keep-id'; then
    echo "PASS: rootless directive -> podman (no sudo) + --userns=keep-id"
else
    echo "FAIL: rootless directive resolution (rc=$RC): $out"; fail=1
fi

# 2) directive honored ANYWHERE (prefixed), e.g. well past line 20
{ i=1; while [ "$i" -le 25 ]; do printf '# filler %s\n' "$i"; i=$((i+1)); done
  printf 'FROM alpine:latest\n#run-dockerfile: rootless --userns=keep-id\n'; } > Dockerfile
run_engine ""
if [ "$RC" -eq 0 ] && [ "$(printf '%s\n' "$out" | sed -n '1p')" = "podman" ]; then
    echo "PASS: prefixed rootless honored after line 20"
else
    echo "FAIL: prefixed rootless after line 20 (rc=$RC): $out"; fail=1
fi

# 3) mandatory value: bare `rootless` with no value is an error
printf '#run-dockerfile: rootless\nFROM alpine:latest\n' > Dockerfile
run_engine ""
if [ "$RC" -ne 0 ] && printf '%s\n' "$out" | grep -Fq -- '--userns='; then
    echo "PASS: missing userns value rejected"
else
    echo "FAIL: missing userns value not rejected (rc=$RC): $out"; fail=1
fi

# 4) value must be a --userns= token
printf '#run-dockerfile: rootless keep-id\nFROM alpine:latest\n' > Dockerfile
run_engine ""
if [ "$RC" -ne 0 ]; then
    echo "PASS: non --userns= value rejected"
else
    echo "FAIL: 'rootless keep-id' was accepted: $out"; fail=1
fi

# 5) prefix-only: the unprefixed #rootless: form is NOT honored (treated as a
#    plain comment) -> rootful default (sudo podman), no error.
printf '#rootless: --userns=keep-id\nFROM alpine:latest\n' > Dockerfile
run_engine ""
if [ "$RC" -eq 0 ] && [ "$(printf '%s\n' "$out" | sed -n '1p')" = "sudo podman" ]; then
    echo "PASS: unprefixed #rootless: ignored (prefix-only)"
else
    echo "FAIL: unprefixed #rootless: was honored (rc=$RC): $out"; fail=1
fi

# 6) conflict: rootless directive + RUN_DOCKERFILE_ENGINE=docker -> error
printf '#run-dockerfile: rootless --userns=keep-id\nFROM alpine:latest\n' > Dockerfile
run_engine "docker"
if [ "$RC" -ne 0 ] && printf '%s\n' "$out" | grep -Fiq podman; then
    echo "PASS: rootless + engine=docker conflict rejected"
else
    echo "FAIL: rootless + engine=docker not rejected (rc=$RC): $out"; fail=1
fi

# 7) rootless requires podman: directive present but podman absent -> error
rm -f "$BIN/podman"
printf '#run-dockerfile: rootless --userns=keep-id\nFROM alpine:latest\n' > Dockerfile
run_engine ""
if [ "$RC" -ne 0 ] && printf '%s\n' "$out" | grep -Fiq podman; then
    echo "PASS: rootless without podman rejected"
else
    echo "FAIL: rootless without podman not rejected (rc=$RC): $out"; fail=1
fi
make_stub podman

rm -f Dockerfile
rm -rf "$WORK"
exit $fail
