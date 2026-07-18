#!/bin/sh
# Test: #option: -e/--env variants pass env vars and preserve across su

set -e

fail=0

# Test #option: -e VAR=val
output=$(./run sh -c 'echo "TEST_A=$TEST_A"') || true
case "$output" in
    *"TEST_A=val_a"*) echo "PASS: #option: -e VAR=val" ;;
    *) echo "FAIL: #option: -e VAR=val - got: $output"; fail=1 ;;
esac

# Test #option: --env VAR=val
output=$(./run sh -c 'echo "TEST_B=$TEST_B"') || true
case "$output" in
    *"TEST_B=val_b"*) echo "PASS: #option: --env VAR=val" ;;
    *) echo "FAIL: #option: --env VAR=val - got: $output"; fail=1 ;;
esac

# Test #option: --env=VAR=val
output=$(./run sh -c 'echo "TEST_C=$TEST_C"') || true
case "$output" in
    *"TEST_C=val_c"*) echo "PASS: #option: --env=VAR=val" ;;
    *) echo "FAIL: #option: --env=VAR=val - got: $output"; fail=1 ;;
esac

exit $fail
