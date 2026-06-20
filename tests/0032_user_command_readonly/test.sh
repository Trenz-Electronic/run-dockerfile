#!/bin/sh
# Test: the script is bind-mounted into the container at /bin/user-command
# read-only, so a (compromised) container cannot overwrite the host script
# through the mount. Checked non-destructively via /proc/self/mountinfo:
# field 5 is the mount point, field 6 its per-mount options.

set -e

opts=$(./run sh -c "awk '\$5 == \"/bin/user-command\" { print \$6 }' /proc/self/mountinfo")

case "$opts" in
    "")
        echo "FAIL: /bin/user-command not found in mountinfo (opts empty)"
        exit 1
        ;;
    ro|ro,*)
        echo "PASS: /bin/user-command is mounted read-only ($opts)"
        exit 0
        ;;
    *)
        echo "FAIL: /bin/user-command is NOT read-only (opts: $opts)"
        exit 1
        ;;
esac
