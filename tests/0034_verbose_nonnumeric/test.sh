#!/bin/sh
# Test: a non-numeric RUN_DOCKERFILE_VERBOSE value does not make info() emit a
# shell "integer expression expected" error. The variable is a flag, so it
# should be compared as a string, not with -eq.

set -e

# Force a rebuild so info() is exercised on the build path.
docker rmi -f 0034_verbose_nonnumeric 2>/dev/null || true

output=$(RUN_DOCKERFILE_VERBOSE=notanumber ./run true 2>&1) || {
    echo "FAIL: run failed with a non-numeric RUN_DOCKERFILE_VERBOSE"
    echo "Output: $output"
    exit 1
}

if echo "$output" | grep -F "integer expression expected" >/dev/null; then
    echo "FAIL: info() broke on non-numeric RUN_DOCKERFILE_VERBOSE"
    echo "Output: $output"
    exit 1
fi

echo "PASS: non-numeric RUN_DOCKERFILE_VERBOSE handled cleanly"
exit 0
