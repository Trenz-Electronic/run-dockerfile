#!/bin/sh
# caps: qemu-arm64
# Test: # platform: arm64 directive runs container on aarch64

set -e

output=$(./run uname -m)

case "$output" in
    *"aarch64"*)
        echo "PASS: Container running on aarch64"
        exit 0
        ;;
    *)
        echo "FAIL: Expected aarch64, got: $output"
        exit 1
        ;;
esac
