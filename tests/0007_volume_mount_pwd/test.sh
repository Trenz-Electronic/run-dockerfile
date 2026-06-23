#!/bin/sh
# Test: Volume mount - $PWD is accessible inside container

set -e

marker=".run-dockerfile-test-$$"
expected="unique-marker-$$"

# Create marker in PWD on host
echo "$expected" > "$marker"

# Read from container
output=$(./run cat "$marker") || {
    rm -f "$marker"
    echo "FAIL: Could not read marker file from container"
    exit 1
}

# Cleanup
rm -f "$marker"

# Verify
if [ "$output" = "$expected" ]; then
    echo "PASS: \$PWD is correctly mounted"
    exit 0
else
    echo "FAIL: Content mismatch: expected='$expected' got='$output'"
    exit 1
fi
