#!/bin/sh
# Test: User mount directive (#usermount:)
# Verifies that:
# - Directories are created if they don't exist (as current user)
# - Existing directories are mounted without error
# - Multiple directories can be mounted (one path per #usermount: line)
# - Environment variables are expanded ($HOME, $PWD)
# - A path containing a space is mounted as a single path
# - Command substitution in a directive is NOT evaluated on the host

set -e

. ../lib/engine.sh

. ../lib/portable.sh

fail=0

# Unique test directory names to avoid conflicts
TESTDIR1="$HOME/.run-dockerfile-test-0021-$$"
TESTDIR2="$HOME/.run-dockerfile-test-0021-multi-$$"
# Exported so build-and-run can expand it inside a #usermount: directive (Test 6).
# Deliberately contains a space.
export DB_SPACE_DIR="$HOME/.run-dockerfile spacetest-0021-$$"

# Cleanup function
cleanup() {
    rm -rf "$TESTDIR1" "$TESTDIR2" "$DB_SPACE_DIR"
    rm -rf test_create test_existing test_multiple test_envvar test_injection test_space
    rm -f "$HOME"/.run-dockerfile-pwned-0021-*
    $ENGINE rmi -f 0021_usermount_create 0021_usermount_existing 0021_usermount_multi test_injection test_space 2>/dev/null || true
}
trap cleanup EXIT

# Clean up any leftovers from previous runs
rm -rf "$TESTDIR1" "$TESTDIR2"

echo "=== Test 1: Create directory that doesn't exist ==="
mkdir -p test_create
cd test_create
cat > Dockerfile <<EOF
#usermount: $TESTDIR1
FROM ubuntu:22.04
EOF
ln -sf ../../../build-and-run run

# Run container - directory should be created and mounted
output=$(./run sh -c "test -d $TESTDIR1 && echo MOUNT_OK" 2>&1) || true
if echo "$output" | grep -q "MOUNT_OK"; then
    echo "PASS: Directory accessible inside container"
else
    echo "FAIL: Directory not accessible inside container"
    echo "Output: $output"
    fail=1
fi

# Verify directory was created on host
if [ -d "$TESTDIR1" ]; then
    echo "PASS: Directory created on host"
else
    echo "FAIL: Directory not created on host"
    fail=1
fi

# Verify ownership (should be current user, not root)
owner_uid=$(stat_uid "$TESTDIR1")
if [ "$owner_uid" = "$(id -u)" ]; then
    echo "PASS: Directory owned by current user"
else
    echo "FAIL: Directory owned by $owner_uid, expected $(id -u)"
    fail=1
fi

# Check for "Created directory" message
if echo "$output" | grep -q "Created directory"; then
    echo "PASS: Creation message shown"
else
    echo "FAIL: Expected 'Created directory' message"
    fail=1
fi
cd ..

echo ""
echo "=== Test 2: Mount existing directory ==="
mkdir -p "$TESTDIR1"
echo "test-marker-0021" > "$TESTDIR1/marker.txt"
mkdir -p test_existing
cd test_existing
cat > Dockerfile <<EOF
#usermount: $TESTDIR1
FROM ubuntu:22.04
EOF
ln -sf ../../../build-and-run run

# Run container - should mount existing directory
output=$(./run cat "$TESTDIR1/marker.txt" 2>&1) || true
if echo "$output" | grep -q "test-marker-0021"; then
    echo "PASS: Existing directory mounted correctly"
else
    echo "FAIL: Could not read file from mounted directory"
    echo "Output: $output"
    fail=1
fi

# Should NOT show "Created directory" message
if echo "$output" | grep -q "Created directory"; then
    echo "FAIL: Should not create already-existing directory"
    fail=1
else
    echo "PASS: No creation message for existing directory"
fi
cd ..

echo ""
echo "=== Test 3: Mount multiple directories (one per line) ==="
rm -rf "$TESTDIR1" "$TESTDIR2"
mkdir -p test_multiple
cd test_multiple
cat > Dockerfile <<EOF
#usermount: $TESTDIR1
#usermount: $TESTDIR2
FROM ubuntu:22.04
EOF
ln -sf ../../../build-and-run run

# Run container - both directories should be created and mounted
output=$(./run sh -c "test -d $TESTDIR1 && test -d $TESTDIR2 && echo BOTH_OK" 2>&1) || true
if echo "$output" | grep -q "BOTH_OK"; then
    echo "PASS: Both directories accessible"
else
    echo "FAIL: Not all directories accessible"
    echo "Output: $output"
    fail=1
fi

# Verify both directories created on host
if [ -d "$TESTDIR1" ] && [ -d "$TESTDIR2" ]; then
    echo "PASS: Both directories created on host"
else
    echo "FAIL: Not all directories created on host"
    fail=1
fi
cd ..

echo ""
echo "=== Test 4: Environment variable expansion ==="
rm -rf "$TESTDIR1"
mkdir -p test_envvar
cd test_envvar
# Use literal $HOME in Dockerfile (will be expanded by build-and-run)
cat > Dockerfile <<'EOF'
#usermount: $HOME/.run-dockerfile-envtest-0021
FROM ubuntu:22.04
EOF
ln -sf ../../../build-and-run run

output=$(./run sh -c "test -d \$HOME/.run-dockerfile-envtest-0021 && echo ENVVAR_OK" 2>&1) || true
if echo "$output" | grep -q "ENVVAR_OK"; then
    echo "PASS: Environment variable expanded correctly"
else
    echo "FAIL: Environment variable not expanded"
    echo "Output: $output"
    fail=1
fi

# Cleanup the envtest dir
rm -rf "$HOME/.run-dockerfile-envtest-0021"
cd ..

echo ""
echo "=== Test 5: Command substitution must NOT execute on host ==="
rm -rf "$TESTDIR1"
MARKER="$HOME/.run-dockerfile-pwned-0021-$$"
rm -f "$MARKER"
mkdir -p test_injection
cd test_injection
# If the path were expanded with eval, this would run touch on the HOST.
# ${IFS} keeps it one shell word so it survives the parser's word-splitting.
cat > Dockerfile <<EOF
#usermount: \$(touch\${IFS}$MARKER)
FROM ubuntu:22.04
EOF
ln -sf ../../../build-and-run run

# The run itself may fail (the literal path is not a valid mount); that is fine.
# The only thing under test is that no host-side code executed.
./run true >/dev/null 2>&1 || true

if [ -e "$MARKER" ]; then
    echo "FAIL: command substitution executed on host (marker file created)"
    rm -f "$MARKER"
    fail=1
else
    echo "PASS: command substitution not executed (treated as literal data)"
fi
cd ..

echo ""
echo "=== Test 6: Path containing a space (single path per line) ==="
rm -rf "$DB_SPACE_DIR"
mkdir -p test_space
cd test_space
# Single-quoted heredoc: $DB_SPACE_DIR stays literal in the Dockerfile and is
# expanded by build-and-run (it is exported) to a path containing a space.
cat > Dockerfile <<'EOF'
#usermount: $DB_SPACE_DIR
FROM ubuntu:22.04
EOF
ln -sf ../../../build-and-run run

# Pass the spaced path as a positional arg ($1) to avoid nested-quoting issues.
output=$(./run sh -c 'test -d "$1" && echo MOUNT_OK' _ "$DB_SPACE_DIR" 2>&1) || true
if echo "$output" | grep -q "MOUNT_OK"; then
    echo "PASS: spaced path mounted as a single directory inside container"
else
    echo "FAIL: spaced path not mounted"
    echo "Output: $output"
    fail=1
fi

# Verify the directory was created on host (not split into two)
if [ -d "$DB_SPACE_DIR" ]; then
    echo "PASS: spaced directory created on host"
else
    echo "FAIL: spaced directory not created on host"
    fail=1
fi

# Verify ownership (current user, not root)
if [ -d "$DB_SPACE_DIR" ]; then
    owner_uid=$(stat_uid "$DB_SPACE_DIR")
    if [ "$owner_uid" = "$(id -u)" ]; then
        echo "PASS: spaced directory owned by current user"
    else
        echo "FAIL: spaced directory owned by $owner_uid, expected $(id -u)"
        fail=1
    fi
fi
cd ..

if [ "$fail" = 0 ]; then
    echo ""
    echo "PASS: All usermount directive tests passed"
fi

exit $fail
