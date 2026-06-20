#!/bin/sh
# Test: deterministic fallback user/group names retry when the first fallback
# already exists with the wrong numeric identity.

set -e

host_user=$(id -un)
host_group=$(id -gn)
host_uid=$(id -u)
host_gid=$(id -g)

conflict_uid=4242
conflict_gid=4243
fallback_conflict_uid=4342
fallback_conflict_gid=4343
group_conflict_gid=4442
group_fallback_conflict_gid=4443

[ "$conflict_uid" = "$host_uid" ] && conflict_uid=5242
[ "$conflict_gid" = "$host_gid" ] && conflict_gid=5243
[ "$fallback_conflict_uid" = "$host_uid" ] && fallback_conflict_uid=5342
[ "$fallback_conflict_gid" = "$host_gid" ] && fallback_conflict_gid=5343
[ "$group_conflict_gid" = "$host_gid" ] && group_conflict_gid=5442
[ "$group_fallback_conflict_gid" = "$host_gid" ] && group_fallback_conflict_gid=5443

expected_user="${host_user}_${host_uid}_a"
expected_group="${host_group}_${host_gid}_a"

cleanup() {
    rm -f Dockerfile.tmp
    docker rmi -f 0039_user_group_fallback_collision 2>/dev/null || true
}
trap cleanup EXIT INT TERM

cat > Dockerfile.tmp <<EOF
FROM alpine:latest
RUN echo "$host_user:x:$conflict_uid:$conflict_gid::/home/$host_user:/bin/sh" >> /etc/passwd \\
 && echo "${host_user}_${host_uid}:x:$fallback_conflict_uid:$fallback_conflict_gid::/home/${host_user}_${host_uid}:/bin/sh" >> /etc/passwd \\
 && echo "$host_group:x:$group_conflict_gid:" >> /etc/group \\
 && echo "${host_group}_${host_gid}:x:$group_fallback_conflict_gid:" >> /etc/group
EOF

docker build -f Dockerfile.tmp -t 0039_user_group_fallback_collision . >/dev/null 2>&1

container_uid=$(./run id -u)
container_gid=$(./run id -g)
container_user=$(./run id -un)
container_groups=$(./run cat /etc/group)
container_passwd=$(./run cat /etc/passwd)

fail=0

if [ "$container_uid" = "$host_uid" ]; then
    echo "PASS: container uid matches host after fallback username collision"
else
    echo "FAIL: container uid is $container_uid, expected $host_uid"
    fail=1
fi

if [ "$container_gid" = "$host_gid" ]; then
    echo "PASS: container gid matches host after fallback group collision"
else
    echo "FAIL: container gid is $container_gid, expected $host_gid"
    fail=1
fi

if [ "$container_user" = "$expected_user" ]; then
    echo "PASS: username retried to $expected_user"
else
    echo "FAIL: username is $container_user, expected $expected_user"
    fail=1
fi

if ! echo "$container_passwd" | awk -F: -v name="$expected_user" -v uid="$host_uid" -v gid="$host_gid" '$1 == name && $3 == uid && $4 == gid { found=1 } END { exit found ? 0 : 1 }'; then
    echo "FAIL: expected passwd entry '$expected_user' with $host_uid:$host_gid"
    fail=1
fi

if echo "$container_groups" | awk -F: -v name="$expected_group" -v gid="$host_gid" '$1 == name && $3 == gid { found=1 } END { exit found ? 0 : 1 }'; then
    echo "PASS: group retried to $expected_group"
else
    echo "FAIL: expected group entry '$expected_group' with GID $host_gid"
    fail=1
fi

exit "$fail"
