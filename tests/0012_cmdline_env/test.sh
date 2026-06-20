#!/bin/sh
# Test: Command-line -e/--env options pass env vars and preserve across su

set -e

fail=0

# Test -e VAR=val
output=$(./run -e TEST_A=val_a sh -c 'echo "TEST_A=$TEST_A"')
case "$output" in
    *"TEST_A=val_a"*) echo "PASS: -e VAR=val" ;;
    *) echo "FAIL: -e VAR=val - got: $output"; fail=1 ;;
esac

# Test --env VAR=val
output=$(./run --env TEST_B=val_b sh -c 'echo "TEST_B=$TEST_B"')
case "$output" in
    *"TEST_B=val_b"*) echo "PASS: --env VAR=val" ;;
    *) echo "FAIL: --env VAR=val - got: $output"; fail=1 ;;
esac

# Test --env=VAR=val
output=$(./run --env=TEST_C=val_c sh -c 'echo "TEST_C=$TEST_C"')
case "$output" in
    *"TEST_C=val_c"*) echo "PASS: --env=VAR=val" ;;
    *) echo "FAIL: --env=VAR=val - got: $output"; fail=1 ;;
esac

# Test multiple -e options
output=$(./run -e TEST_D=val_d -e TEST_E=val_e sh -c 'echo "D=$TEST_D E=$TEST_E"')
case "$output" in
    *"D=val_d"*"E=val_e"*) echo "PASS: multiple -e options" ;;
    *) echo "FAIL: multiple -e options - got: $output"; fail=1 ;;
esac

exit $fail
