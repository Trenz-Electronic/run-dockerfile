#!/bin/sh
# Test: bare ./run fails on the host with a user-facing error.

set -e

status=0
output=$(./run 2>&1) || status=$?

if [ "$status" -eq 0 ]; then
    echo "FAIL: expected non-zero exit for bare ./run"
    exit 1
fi

if [ -z "$output" ]; then
    echo "FAIL: expected an error message for bare ./run"
    exit 1
fi

if echo "$output" | grep -F "USER USERID GROUPID" >/dev/null; then
    echo "FAIL: bare ./run exposed internal user-command usage"
    echo "Output: $output"
    exit 1
fi

if ! echo "$output" | grep -F "Run './run --help' for usage." >/dev/null; then
    echo "FAIL: bare ./run did not mention --help"
    echo "Output: $output"
    exit 1
fi

echo "PASS: bare ./run fails with a user-facing error"
