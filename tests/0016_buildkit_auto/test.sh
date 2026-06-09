#!/bin/sh
# Test: BuildKit is enabled by default.
# The Dockerfile uses `RUN --mount=type=tmpfs,...`, which only the BuildKit
# builder understands, so a successful build proves BuildKit is active without
# the user having to set anything.

set -e

# Force a rebuild so the build actually runs.
docker rmi -f 0016_buildkit_auto 2>/dev/null || true

output=$(./run echo "buildkit test" 2>&1)

case "$output" in
    *"buildkit test"*)
        echo "PASS: BuildKit enabled by default (RUN --mount build succeeded)"
        exit 0
        ;;
    *)
        echo "FAIL: RUN --mount build did not succeed with BuildKit default on"
        echo "Output: $output"
        exit 1
        ;;
esac
