#!/bin/sh
# Test: Group name conflict - host group name exists with different GID

set -e

. ../lib/engine.sh

host_group=$(id -gn)
host_gid=$(id -g)
conflict_gid=9999

# Generate Dockerfile with conflicting group
cat > Dockerfile.tmp <<EOF
FROM alpine:latest
RUN echo "$host_group:x:$conflict_gid::" >> /etc/group
EOF

# Build image with conflicting group (same engine ./run will use)
$ENGINE build -f Dockerfile.tmp -t 0015_user_mapping_conflict . >/dev/null 2>&1

# Run and check group mapping. If another image group already has the host GID,
# reverse lookup (`id -gn`) may return that first image group instead of the
# appended conflict-renamed alias.
container_group=$(./run id -gn)
container_gid=$(./run id -g)
container_groups=$(./run cat /etc/group)

# Cleanup
rm -f Dockerfile.tmp

fail=0

# Group should be renamed to avoid the host group name conflict.
expected_group="${host_group}_${host_gid}"
if ! echo "$container_groups" | awk -F: -v name="$expected_group" -v gid="$host_gid" '$1 == name && $3 == gid { found=1 } END { exit found ? 0 : 1 }'; then
    echo "FAIL: Expected group alias '$expected_group' with GID $host_gid in /etc/group"
    fail=1
fi

if ! echo "$container_groups" | awk -F: -v name="$container_group" -v gid="$host_gid" '$1 == name && $3 == gid { found=1 } END { exit found ? 0 : 1 }'; then
    echo "FAIL: Reported group '$container_group' does not map to host GID $host_gid"
    fail=1
fi

# GID should still match host
if [ "$container_gid" != "$host_gid" ]; then
    echo "FAIL: GID mismatch: expected $host_gid, got $container_gid"
    fail=1
fi

if [ "$fail" = 0 ]; then
    echo "PASS: Group conflict handled (alias=$expected_group, reported=$container_group, gid=$container_gid)"
fi

exit $fail
