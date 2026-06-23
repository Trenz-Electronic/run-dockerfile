#!/bin/sh
# Test: Volume mount - $HOME is accessible inside container

set -e

marker="$HOME/.run-dockerfile-test-$$"
expected="unique-marker-$$"

# Create marker on host
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
    echo "PASS: \$HOME is correctly mounted"
    exit 0
else
    echo "FAIL: Content mismatch: expected='$expected' got='$output'"
    exit 1
fi
