#!/bin/sh
# Test: build-and-run bakes itself into the image at /bin/user-command (a root-owned
# 0755 file in an image layer) instead of bind-mounting the host script there. This
# keeps the hardening - the host script is never exposed to the container, and the
# unprivileged container user cannot overwrite the baked copy - WITHOUT adding a
# read-only real-filesystem mount. Such a mount breaks tools that enumerate
# /proc/mounts for a writability/disk-space check (e.g. RPM's rootfs install, which
# aborts with "installing package ... on /bin/user-command rdonly filesystem").

set -e

# (1) /bin/user-command must NOT be a bind mount. Field 5 of mountinfo is the mount
# point; an entry here would mean the host script is mounted in (the old behavior).
mounted=$(./run sh -c "awk '\$5 == \"/bin/user-command\" { print \"mounted\" }' /proc/self/mountinfo")
if [ -n "$mounted" ]; then
    echo "FAIL: /bin/user-command is bind-mounted; expected a baked-in image file"
    exit 1
fi

# (2) It must be baked in: present, executable, and owned by root (uid 0) so the
# mapped unprivileged container user cannot rewrite it.
result=$(./run sh -c '
    uid=$(stat -c %u /bin/user-command 2>/dev/null || echo NA)
    if [ -x /bin/user-command ] && [ "$uid" = 0 ]; then
        echo BAKED_ROOT_EXEC
    else
        echo "BAD x=$([ -x /bin/user-command ] && echo 1 || echo 0) uid=$uid"
    fi
')

case "$result" in
    *BAKED_ROOT_EXEC*)
        echo "PASS: /bin/user-command is baked in, executable, root-owned (not a mount)"
        exit 0
        ;;
    *)
        echo "FAIL: /bin/user-command not baked-in as expected ($result)"
        exit 1
        ;;
esac
