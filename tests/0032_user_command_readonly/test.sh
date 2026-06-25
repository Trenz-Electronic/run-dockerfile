#!/bin/sh
# Test: build-and-run bakes its in-container entry script into the image at
# /bin/run-dockerfile-user-command (a root-owned 0755 file) instead of bind-mounting
# the host script there. This keeps the hardening - the host script is never exposed
# to the container, and the unprivileged user cannot overwrite the baked copy -
# WITHOUT adding a read-only real-filesystem mount that breaks tools enumerating
# /proc/mounts for a writability check (e.g. RPM-based rootfs builds).

set -e

# (1) /bin/run-dockerfile-user-command must NOT be a bind mount. Field 5 of mountinfo is the mount
# point; an entry here would mean the host script is mounted in (the old behavior).
mounted=$(./run sh -c "awk '\$5 == \"/bin/run-dockerfile-user-command\" { print \"mounted\" }' /proc/self/mountinfo")
if [ -n "$mounted" ]; then
    echo "FAIL: /bin/run-dockerfile-user-command is bind-mounted; expected a baked-in image file"
    exit 1
fi

# (2) It must be baked in: present, executable, and owned by root (uid 0) so the
# mapped unprivileged container user cannot rewrite it.
result=$(./run sh -c '
    uid=$(stat -c %u /bin/run-dockerfile-user-command 2>/dev/null || echo NA)
    if [ -x /bin/run-dockerfile-user-command ] && [ "$uid" = 0 ]; then
        echo BAKED_ROOT_EXEC
    else
        echo "BAD x=$([ -x /bin/run-dockerfile-user-command ] && echo 1 || echo 0) uid=$uid"
    fi
')

case "$result" in
    *BAKED_ROOT_EXEC*)
        echo "PASS: /bin/run-dockerfile-user-command is baked in, executable, root-owned (not a mount)"
        exit 0
        ;;
    *)
        echo "FAIL: /bin/run-dockerfile-user-command not baked-in as expected ($result)"
        exit 1
        ;;
esac
