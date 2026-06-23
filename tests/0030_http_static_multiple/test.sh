#!/bin/sh
# Test: multiple #http.static: directives each serve their OWN directory.
# Regression for the shared-port-file bug, where the second directive reused
# the first server's port and its build-arg URL pointed at the wrong directory.

set -e

test_dir="$(cd "$(dirname "$0")" && pwd)"
marker_a="content-a-$$"
marker_b="content-b-$$"

mkdir -p "$test_dir/data-a" "$test_dir/data-b"
echo "$marker_a" > "$test_dir/data-a/marker-a.txt"
echo "$marker_b" > "$test_dir/data-b/marker-b.txt"

cleanup() {
    rm -rf "$test_dir/data-a" "$test_dir/data-b"
}
trap cleanup EXIT INT TERM

# Force a rebuild so the HTTP servers actually start.
docker rmi -f 0030_http_static_multiple 2>/dev/null || true

# With the bug, the BETA build-arg points at the ALPHA server and the build
# fails fetching marker-b.txt; the build only succeeds when both servers map
# to their own directory.
output=$(./run cat /tmp/a.txt /tmp/b.txt) || {
    echo "FAIL: build/run failed - second #http.static: server likely mismapped"
    exit 1
}

if ! echo "$output" | grep -F "$marker_a" >/dev/null; then
    echo "FAIL: first server (ALPHA) content missing"
    echo "Got: $output"
    exit 1
fi
if ! echo "$output" | grep -F "$marker_b" >/dev/null; then
    echo "FAIL: second server (BETA) content missing"
    echo "Got: $output"
    exit 1
fi

# Temp port files must not leak after the build (finding 2).
leftover=$(ls /tmp/run-dockerfile-http-port-*.txt 2>/dev/null || true)
if [ -n "$leftover" ]; then
    echo "FAIL: HTTP port files leaked in /tmp:"
    echo "$leftover"
    exit 1
fi

echo "PASS: both #http.static: directives served their own directory, no temp leak"
exit 0
