#!/bin/sh
# Test: a host bind-mount path containing a space is passed to docker verbatim.
# Before the bash-array refactor, the unquoted $CMDLINE_DOCKER_ARGS / $PWD / $MDIR
# expansions word-split such a path and the run failed.

set -e

fail=0

td="/tmp/db booster 0022-$$"   # note the spaces

cleanup() {
    rm -rf "$td"
    docker rmi -f 0022_space_in_path 2>/dev/null || true
}
trap cleanup EXIT

mkdir -p "$td"
echo "space_marker_$$" > "$td/marker"

# Bind-mount the spaced host path (same path inside the container) and read it back.
output=$(./run -v "$td:$td:ro" cat "$td/marker")
if [ "$output" = "space_marker_$$" ]; then
    echo "PASS: bind-mount path with a space passed verbatim"
else
    echo "FAIL: expected 'space_marker_$$', got: '$output'"
    fail=1
fi

exit $fail
