#!/bin/sh
# Test: ENV vars from Dockerfile are preserved across the internal su drop

set -e

output=$(./run sh -c 'echo "TEST_VAR=$TEST_VAR"')

# Check output contains the expected value
case "$output" in
    *"TEST_VAR=hello_from_dockerfile"*)
        echo "PASS: ENV var preserved across su"
        exit 0
        ;;
    *)
        echo "FAIL: Expected TEST_VAR=hello_from_dockerfile in output"
        echo "Got: $output"
        exit 1
        ;;
esac
