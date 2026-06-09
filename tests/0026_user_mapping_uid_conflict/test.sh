#!/bin/sh
# Test: User NAME conflict - the image already contains a user with the host's
# username but a DIFFERENT uid (and gid). The container must still run with the
# host's uid/gid so that bind-mounted files stay accessible; it must NOT silently
# reuse the image's same-name user (which would run under the wrong uid).

set -e

host_user=$(id -un)
host_uid=$(id -u)
host_gid=$(id -g)

# A uid/gid that is NOT the host's, baked into the image as a same-name conflict.
conflict_id=4242
[ "$conflict_id" = "$host_uid" ] && conflict_id=4243

# Image pre-creates "$host_user" at the conflicting uid/gid.
cat > Dockerfile.tmp <<EOF
FROM alpine:latest
RUN echo "$host_user:x:$conflict_id:$conflict_id::/home/$host_user:/bin/sh" >> /etc/passwd && echo "$host_user:x:$conflict_id:" >> /etc/group
EOF

docker build -f Dockerfile.tmp -t 0026_user_mapping_uid_conflict . >/dev/null 2>&1

container_uid=$(./run id -u 2>/dev/null)
container_gid=$(./run id -g 2>/dev/null)

rm -f Dockerfile.tmp

fail=0

if [ "$container_uid" = "$host_uid" ]; then
    echo "PASS: container uid matches host ($host_uid) despite same-name image user at uid $conflict_id"
else
    echo "FAIL: container uid is $container_uid, expected host uid $host_uid (reused the image's same-name user)"
    fail=1
fi

if [ "$container_gid" = "$host_gid" ]; then
    echo "PASS: container gid matches host ($host_gid)"
else
    echo "FAIL: container gid is $container_gid, expected host gid $host_gid"
    fail=1
fi

if [ "$fail" = 0 ]; then
    echo "PASS: user name/uid conflict handled (runs with host uid/gid)"
fi

exit $fail
