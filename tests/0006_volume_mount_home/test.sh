#!/bin/sh
# caps: home-bind
# Test: Volume mount - $HOME is accessible inside container
#
# Requires the `home-bind` capability: a bind-mounted private (mode-700) $HOME must
# be readable by the in-container host-matching user. Every cell provides this except
# macos-podman-rootless, where the podman-machine virtiofs share + rootless user
# namespace map the host user to container root, leaving a 700 $HOME unreadable by the
# unprivileged user (build-and-run errors out early there; see CLAUDE.md).

set -e

. ../lib/skip.sh
. ../lib/engine.sh

# In CI the home-bind cap pre-skips this on macos-podman-rootless. In local dev (caps
# unenforced) self-skip there too: rootless Podman on macOS maps the host user to
# container root, so a bind-mounted private $HOME is unreadable and build-and-run
# errors out by design (see CLAUDE.md). $ENGINE mirrors build-and-run's resolution.
if [ "$(uname -s)" = Darwin ] && [ "$($ENGINE info --format '{{.Host.Security.Rootless}}' 2>/dev/null)" = true ]; then
    skip "rootless Podman on macOS cannot bind-mount a private \$HOME readable by the container user"
fi

marker="$HOME/.run-dockerfile-test-$$"
expected="unique-marker-$$"

# Create marker on host
echo "$expected" > "$marker"

# Read from container
output=$(./run cat "$marker") || {
    rm -f "$marker"
    echo "FAIL: Could not read marker file from container"
    exit 1
}

# Cleanup
rm -f "$marker"

# Verify
if [ "$output" = "$expected" ]; then
    echo "PASS: \$HOME is correctly mounted"
    exit 0
else
    echo "FAIL: Content mismatch: expected='$expected' got='$output'"
    exit 1
fi
