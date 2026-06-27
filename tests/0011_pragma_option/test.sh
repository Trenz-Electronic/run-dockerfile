#!/bin/sh
# caps: cgroups
# Test: #option: pragma passes options to docker run

set -e

# Check CPU quota is set (cgroup v2)
output=$(./run cat /sys/fs/cgroup/cpu.max 2>/dev/null) || {
    # Try cgroup v1
    output=$(./run cat /sys/fs/cgroup/cpu/cpu.cfs_quota_us 2>/dev/null) || {
        echo "FAIL: Could not read CPU cgroup limits"
        exit 1
    }
}

# cpu.max format: "quota period" e.g., "100000 100000" for 1 CPU
# cgroup v1: quota in microseconds, 100000 = 1 CPU
case "$output" in
    100000*)
        echo "PASS: CPU limit applied (--cpus 1)"
        exit 0
        ;;
    *)
        echo "FAIL: Unexpected CPU limit: $output"
        exit 1
        ;;
esac
