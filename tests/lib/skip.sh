#!/bin/sh
# Shared test helper: whole-test self-skip for environment realities the test's
# declared `# caps:` cannot predict (e.g. rootless Podman cannot start inside a
# nested unprivileged LXC, even though the host "has" podman). Exit code 77 is
# the SKIP sentinel that tests/run distinguishes from PASS (0) and FAIL (other).
#
# Capability gating that CAN be predicted up front should be expressed with a
# `# caps:` line and left to tests/run to pre-skip; reserve skip() for the
# unpredictable. On a cap-enforcing cell (RUN_DOCKERFILE_CELL_CAPS set) where the
# test's caps ARE provided, an exit-77 is treated as a failure, so a cell that is
# supposed to support a capability cannot quietly skip the test that proves it.
#
# POSIX sh.
skip() {
    echo "SKIP: $1"
    exit 77
}
