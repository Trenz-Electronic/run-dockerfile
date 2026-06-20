#!/bin/sh
# Test: User mapping - container user matches host UID/GID/group
# Note: group name may be renamed if it conflicts (e.g., "users" -> "users_1000")

set -e

host_user=$(id -un)
host_group=$(id -gn)
host_uid=$(id -u)
host_gid=$(id -g)

container_user=$(./run id -un)
container_group=$(./run id -gn)
container_uid=$(./run id -u)
container_gid=$(./run id -g)
container_groups=$(./run cat /etc/group)

fail=0

if [ "$host_user" != "$container_user" ]; then
    echo "FAIL: username mismatch: host=$host_user container=$container_user"
    fail=1
fi

if [ "$host_uid" != "$container_uid" ]; then
    echo "FAIL: UID mismatch: host=$host_uid container=$container_uid"
    fail=1
fi

if [ "$host_gid" != "$container_gid" ]; then
    echo "FAIL: GID mismatch: host=$host_gid container=$container_gid"
    fail=1
fi

# Group name preservation is best-effort. If the image already has another
# group with the host GID, reverse lookup (`id -gn`) may report that first
# image group. The hard requirement is numeric GID matching, plus a forward
# lookup alias for the host group name (or conflict-renamed alias).
group_alias_ok=0
if echo "$container_groups" | awk -F: -v name="$host_group" -v gid="$host_gid" '$1 == name && $3 == gid { found=1 } END { exit found ? 0 : 1 }'; then
    group_alias_ok=1
elif echo "$container_groups" | awk -F: -v name="${host_group}_${host_gid}" -v gid="$host_gid" '$1 == name && $3 == gid { found=1 } END { exit found ? 0 : 1 }'; then
    group_alias_ok=1
fi

container_group_gid_ok=0
if echo "$container_groups" | awk -F: -v name="$container_group" -v gid="$host_gid" '$1 == name && $3 == gid { found=1 } END { exit found ? 0 : 1 }'; then
    container_group_gid_ok=1
fi

if [ "$group_alias_ok" != 1 ]; then
    echo "FAIL: no host group alias with GID $host_gid found in container /etc/group"
    fail=1
fi

if [ "$container_group_gid_ok" != 1 ]; then
    echo "FAIL: reported group '$container_group' does not map to host GID $host_gid"
    fail=1
fi

if [ "$fail" = 0 ]; then
    echo "PASS: User mapping correct (user=$host_user group=$container_group uid=$host_uid gid=$host_gid)"
fi

exit $fail
