#!/bin/sh
# Test: Copy home files directive (#copy.home:)
# Verifies that:
# - Single file copying works
# - Multiple files copying works
# - Missing files cause error
# - Files are extracted to correct location
# - A filename containing a space is handled (one path per #copy.home: line)

set -e

. ../lib/engine.sh

fail=0

# Enable verbose mode to see informative messages
export RUN_DOCKERFILE_VERBOSE=1

# Setup test files in $HOME
echo "test license content" > "$HOME/.test-license-0019.dat"
mkdir -p "$HOME/.config/test-tool-0019"
echo "test config" > "$HOME/.config/test-tool-0019/config.json"

# Clean up any existing images
$ENGINE rmi -f 0019_copy_single 2>/dev/null || true
$ENGINE rmi -f 0019_copy_multiple 2>/dev/null || true
rm -f /tmp/run-dockerfile-home-files-*.tar.gz 2>/dev/null || true

echo "=== Test 1: Copy single file from home ==="
mkdir -p test_single
cd test_single
cat > Dockerfile <<'EOF'
#copy.home: .test-license-0019.dat
FROM ubuntu:22.04
EOF
ln -sf ../../../build-and-run run
output=$(./run cat ~/.test-license-0019.dat 2>&1) || true
case "$output" in
    *"test license content"*)
        echo "PASS: Single file copied successfully"
        ;;
    *)
        echo "FAIL: File not found in container"
        echo "Output: $output"
        fail=1
        ;;
esac
# Check that the message about collecting files was shown
if echo "$output" | grep -q "Collected home files for container"; then
    echo "PASS: Informative message shown"
else
    echo "FAIL: Expected 'Collected home files' message"
    fail=1
fi
if ls /tmp/run-dockerfile-home-files-*.tar.gz >/dev/null 2>&1; then
    echo "FAIL: #copy.home: temp archive was left in /tmp"
    ls /tmp/run-dockerfile-home-files-*.tar.gz 2>/dev/null || true
    fail=1
else
    echo "PASS: #copy.home: temp archive cleaned up"
fi
cd ..

echo ""
echo "=== Test 2: Copy multiple files from home ==="
mkdir -p test_multiple
cd test_multiple
cat > Dockerfile <<'EOF'
#copy.home: .test-license-0019.dat
#copy.home: .config/test-tool-0019/config.json
FROM ubuntu:22.04
EOF
ln -sf ../../../build-and-run run
output=$(./run sh -c 'cat ~/.test-license-0019.dat && cat ~/.config/test-tool-0019/config.json' 2>&1) || true
if echo "$output" | grep -q "test license content" && echo "$output" | grep -q "test config"; then
    echo "PASS: Multiple files copied successfully"
else
    echo "FAIL: Not all files found in container"
    echo "Output: $output"
    fail=1
fi
cd ..

echo ""
echo "=== Test 2b: Copied files are owned by container user ==="
cd test_multiple
output=$(./run sh -c 'stat -c "%u:%g" ~/.test-license-0019.dat ~/.config/test-tool-0019/config.json ~/.config/test-tool-0019 ~/.config') || true
expected_id="$(id -u):$(id -g)"
bad_lines=$(echo "$output" | grep -c -v "^${expected_id}$" | tr -d ' ') || true
if [ "$bad_lines" = "0" ]; then
    echo "PASS: All copied files and parent dirs owned by user ($expected_id)"
else
    echo "FAIL: Expected all lines to be $expected_id"
    echo "Output: $output"
    fail=1
fi
cd ..

echo ""
echo "=== Test 3: Missing file causes error ==="
mkdir -p test_missing
cd test_missing
cat > Dockerfile <<'EOF'
#copy.home: .nonexistent-file-0019.dat
FROM ubuntu:22.04
EOF
ln -sf ../../../build-and-run run
if ./run echo "should not run" 2>&1 | grep -q "ERROR: Failed to collect files"; then
    echo "PASS: Missing file error detected correctly"
else
    echo "FAIL: Expected error for missing file"
    fail=1
fi
cd ..

echo ""
echo "=== Test 4: Filename containing a space ==="
echo "spaced license $$" > "$HOME/.has space-0019.dat"
mkdir -p test_space
cd test_space
# One path per #copy.home: line, so the whole value (space and all) is one file.
cat > Dockerfile <<'EOF'
#copy.home: .has space-0019.dat
FROM ubuntu:22.04
EOF
ln -sf ../../../build-and-run run
# `|| true` so a regression (./run aborting with "Failed to collect files")
# reports FAIL cleanly instead of tripping set -e and skipping cleanup.
output=$(./run cat "$HOME/.has space-0019.dat" 2>&1) || true
case "$output" in
    *"spaced license $$"*)
        echo "PASS: File with a space in its name copied successfully"
        ;;
    *)
        echo "FAIL: Spaced file not collected/extracted (was it split on the space?)"
        echo "Output: $output"
        fail=1
        ;;
esac
cd ..

# Cleanup
rm -f "$HOME/.test-license-0019.dat" "$HOME/.has space-0019.dat"
rm -rf "$HOME/.config/test-tool-0019"
rm -rf test_single test_multiple test_missing test_space
$ENGINE rmi -f 0019_copy_single 0019_copy_multiple test_space 2>/dev/null || true

if [ "$fail" = 0 ]; then
    echo ""
    echo "PASS: All copy.home directive tests passed"
fi

exit $fail
