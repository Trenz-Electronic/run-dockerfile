#!/bin/sh
# caps: python3
# Test: #http.static: pragma serves files during build
# Uses relative path (http-data) which resolves from Dockerfile directory

set -e

. ../lib/engine.sh

# Get the directory where this test lives
test_dir="$(cd "$(dirname "$0")" && pwd)"
http_dir="$test_dir/http-data"
expected="http-static-test-content-$$"

# Setup: create directory with marker file (relative to Dockerfile dir)
mkdir -p "$http_dir"
echo "$expected" > "$http_dir/marker.txt"

# Force rebuild by removing image
$ENGINE rmi -f 0008_pragma_http_static 2>/dev/null || true

# Run (triggers build which fetches via HTTP using relative path)
output=$(./run cat /tmp/fetched.txt) || {
    rm -rf "$http_dir"
    echo "FAIL: Build or run failed"
    exit 1
}

# Cleanup
rm -rf "$http_dir"

# Verify
if [ "$output" = "$expected" ]; then
    echo "PASS: HTTP static file served during build (relative path)"
    exit 0
else
    echo "FAIL: Content mismatch: expected='$expected' got='$output'"
    exit 1
fi
