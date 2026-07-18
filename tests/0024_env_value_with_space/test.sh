#!/bin/sh
# Test: an env var value containing a space survives end-to-end through BOTH shells.
# Host side: -e "GREETING=hello world" must reach docker as a single argument
# (bash array). Container side: it must be reconstructed across the su privilege
# drop without re-splitting (POSIX `set -- "$var=$val" "$@"`).
# Before the refactor this broke in both places.

set -e

. ../lib/engine.sh

fail=0

cleanup() {
    $ENGINE rmi -f 0024_env_value_with_space 2>/dev/null || true
}
trap cleanup EXIT

output=$(./run -e "GREETING=hello world" sh -c 'printf %s "$GREETING"') || true
if [ "$output" = "hello world" ]; then
    echo "PASS: env value with a space preserved across su"
else
    echo "FAIL: expected 'hello world', got: '$output'"
    fail=1
fi

exit $fail
