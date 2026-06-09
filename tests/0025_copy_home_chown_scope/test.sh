#!/bin/sh
# Test: #copy.home: ownership fix is scoped to the copied entries.
# A pre-existing, NON-copied file in the container's $HOME (here a root-owned
# decoy baked into the image) must keep its ownership after a #copy.home: run.
# The old `chown -R "$USERID:$GROUPID" .` over $HOME would re-own it; the fix
# chowns only the copied files and the parent dirs leading to them.

set -e

fail=0

SRC="$HOME/.copyhome-src-0025-$$"          # the file we ask #copy.home: to copy
DECOY_NAME=".decoy-0025-$$"                 # root-owned, NOT copied
DECOY="$HOME/$DECOY_NAME"

cleanup() {
    rm -f "$SRC"
    rm -rf test_scope
    docker rmi -f test_scope 2>/dev/null || true
}
trap cleanup EXIT

echo "copyhome content $$" > "$SRC"

mkdir -p test_scope
cd test_scope
# Bake a root-owned decoy at the container's $HOME path. The default mount is the
# project dir (not $HOME), so $HOME inside the container is the image filesystem
# and the decoy is present at run time.
cat > Dockerfile <<EOF
#copy.home: .copyhome-src-0025-$$
FROM ubuntu:22.04
RUN mkdir -p "$HOME" && : > "$DECOY" && chown 0:0 "$DECOY"
EOF
ln -sf ../../../build-and-run run

# Report ownership (uid) of the decoy and the copied file from inside the container.
# Paths are passed as positional args so they need no in-line quoting.
output=$(./run sh -c 'echo "decoy=$(stat -c %u "$1")"; echo "src=$(stat -c %u "$2")"' _ "$DECOY" "$SRC" 2>&1)

if echo "$output" | grep -q "^src=$(id -u)$"; then
    echo "PASS: copied file owned by container user"
else
    echo "FAIL: copied file not owned by user"
    echo "Output: $output"
    fail=1
fi

if echo "$output" | grep -q "^decoy=0$"; then
    echo "PASS: pre-existing \$HOME file ownership untouched (chown is scoped)"
else
    echo "FAIL: pre-existing \$HOME file was re-owned (recursive chown not scoped)"
    echo "Output: $output"
    fail=1
fi
cd ..

if [ "$fail" = 0 ]; then
    echo ""
    echo "PASS: copy.home chown-scope test passed"
fi

exit $fail
