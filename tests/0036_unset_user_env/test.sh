#!/bin/sh
# Test: the host username is resolved from `id -un`, not the $USER environment
# variable. docker-booster must map the user correctly even when $USER is unset
# (cron, CI, `env -i`, minimal shells) and must NOT trust a stale/wrong $USER.
#
# Regression test for the fix that replaced "$USER" with "$(id -un)" in the
# user-command argument vector. Under the old code:
#   - $USER unset  -> empty username -> malformed /etc/passwd entry + failing `su ""`
#   - $USER=bogus  -> container ran as "bogus" instead of the real host user

set -e

host_user=$(id -un)
host_uid=$(id -u)
host_gid=$(id -g)

fail=0

# 1. $USER unset: the user must still be mapped from `id`.
container_user=$(env -u USER ./run id -un)
container_uid=$(env -u USER ./run id -u)
container_gid=$(env -u USER ./run id -g)

if [ -z "$container_user" ]; then
    echo "FAIL: container username is empty when \$USER is unset"
    fail=1
elif [ "$container_user" != "$host_user" ]; then
    echo "FAIL: username mismatch with \$USER unset: host=$host_user container=$container_user"
    fail=1
fi

if [ "$container_uid" != "$host_uid" ]; then
    echo "FAIL: UID mismatch with \$USER unset: host=$host_uid container=$container_uid"
    fail=1
fi

if [ "$container_gid" != "$host_gid" ]; then
    echo "FAIL: GID mismatch with \$USER unset: host=$host_gid container=$container_gid"
    fail=1
fi

# 2. A stale/wrong $USER must not leak into the mapping: identity comes from `id`.
container_user_bogus=$(USER=definitely_not_the_user ./run id -un)
if [ "$container_user_bogus" != "$host_user" ]; then
    echo "FAIL: stale \$USER leaked into mapping: expected=$host_user container=$container_user_bogus"
    fail=1
fi

if [ "$fail" = 0 ]; then
    echo "PASS: user mapped from id -un regardless of \$USER (user=$host_user uid=$host_uid gid=$host_gid)"
fi

exit $fail
