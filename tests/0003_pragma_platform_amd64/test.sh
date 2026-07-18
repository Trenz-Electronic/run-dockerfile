#!/bin/sh
# caps: qemu-amd64
# Test: # platform: amd64 directive runs container on x86_64

set -e

output=$(./run uname -m) || true

case "$output" in
    *"x86_64"*)
        echo "PASS: Container running on x86_64"
        exit 0
        ;;
    *)
        echo "FAIL: Expected x86_64, got: $output"
        exit 1
        ;;
esac
