#!/bin/sh
# Test: a container directory whose name is not a valid Docker image name
# (e.g. it contains uppercase letters) fails early with a clear, actionable
# message instead of a cryptic `docker build` reference-format error.

set -e

test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$test_dir/../.." && pwd)"
bad_dir="$test_dir/Bad-Name"

cleanup() {
    rm -rf "$bad_dir"
}
trap cleanup EXIT INT TERM

mkdir -p "$bad_dir"
echo "FROM alpine:latest" > "$bad_dir/Dockerfile"
ln -sf "$repo_root/build-and-run" "$bad_dir/run"

status=0
output=$(cd "$test_dir" && ./Bad-Name/run true 2>&1) || status=$?

if [ "$status" -eq 0 ]; then
    echo "FAIL: expected non-zero exit for invalid image name, got 0"
    echo "Output: $output"
    exit 1
fi

if echo "$output" | grep -F "is not a valid Docker image name" >/dev/null; then
    echo "PASS: invalid container directory name fails with a clear message"
    exit 0
else
    echo "FAIL: missing friendly error for invalid image name"
    echo "Output: $output"
    exit 1
fi
