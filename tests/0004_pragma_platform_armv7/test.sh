#!/bin/sh
# caps: qemu-armv7
# Test: # platform: arm/v7 directive runs container on armv7l

set -e

output=$(./run uname -m)

case "$output" in
    *"armv7l"*)
        echo "PASS: Container running on armv7l"
        exit 0
        ;;
    *)
        echo "FAIL: Expected armv7l, got: $output"
        exit 1
        ;;
esac
