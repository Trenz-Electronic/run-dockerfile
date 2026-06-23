#!/bin/sh
# Test: Command-line docker options are passed through

set -e

. ../lib/portable.sh

fail=0

# Test --network host (verify by checking hostname matches host where Docker
# implements host networking that way; Docker Desktop on macOS accepts the option
# but does not make the container hostname equal the host hostname).
host_hostname=$(hostname)
output=$(./run --network host hostname)
if is_docker_desktop_host_network; then
    echo "PASS: --network host accepted"
elif [ "$output" = "$host_hostname" ]; then
    echo "PASS: --network host"
else
    echo "FAIL: --network host - expected $host_hostname, got: $output"
    fail=1
fi

# Test -v volume mount
test_file="/tmp/run-dockerfile-test-$$"
echo "test_content_$$" > "$test_file"
output=$(./run -v "$test_file:/test_mount:ro" cat /test_mount)
rm -f "$test_file"
if [ "$output" = "test_content_$$" ]; then
    echo "PASS: -v volume mount"
else
    echo "FAIL: -v volume mount - got: $output"
    fail=1
fi

# Test --cpus (verify cgroup limit is set)
output=$(./run --cpus 2 cat /sys/fs/cgroup/cpu.max 2>/dev/null || ./run --cpus 2 cat /sys/fs/cgroup/cpu/cpu.cfs_quota_us 2>/dev/null)
case "$output" in
    200000*)
        echo "PASS: --cpus 2"
        ;;
    *)
        echo "FAIL: --cpus 2 - unexpected limit: $output"
        fail=1
        ;;
esac

# Test -w/--workdir (verify working directory changed)
output=$(./run -w /tmp pwd)
if [ "$output" = "/tmp" ]; then
    echo "PASS: -w /tmp"
else
    echo "FAIL: -w /tmp - expected /tmp, got: $output"
    fail=1
fi

exit $fail
