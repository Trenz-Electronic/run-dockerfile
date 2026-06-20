#!/bin/sh
# Test: a command-line -e whose variable name embeds shell metacharacters is
# NOT executed when the container half dereferences the preserved env vars.
# The name "X;touch /tmp/booster-injected" must be rejected, not eval'd.

set -e

# The container half evaluates DOCKER_PRESERVE_ENV; with the injection bug the
# semicolon command runs during user setup and creates the marker file.
output=$(./run -e 'X;touch /tmp/booster-injected=1' \
    sh -c '[ -e /tmp/booster-injected ] && echo INJECTED || echo SAFE')

case "$output" in
    *INJECTED*)
        echo "FAIL: a crafted -e name was executed inside the container"
        echo "Output: $output"
        exit 1
        ;;
    *SAFE*)
        echo "PASS: crafted -e name was rejected, not evaluated"
        exit 0
        ;;
    *)
        echo "FAIL: unexpected output"
        echo "Output: $output"
        exit 1
        ;;
esac
