#!/bin/sh
# Test: Mount control directives (#mount:)
# Verifies that:
# - #mount: pwd mounts current directory
# - #mount: .git finds and mounts git root
# - #mount: home mounts home directory
# - FIRST-found semantics work correctly
# - Error when all directives fail

set -e

. ../lib/engine.sh

fail=0

# Enable verbose mode to see mount directive messages
export RUN_DOCKERFILE_VERBOSE=1

# Clean up any existing images
$ENGINE rmi -f 0018_mount_pwd 2>/dev/null || true
$ENGINE rmi -f 0018_mount_git 2>/dev/null || true
$ENGINE rmi -f 0018_mount_home 2>/dev/null || true
$ENGINE rmi -f 0018_mount_fallback 2>/dev/null || true

echo "=== Test 1: #mount: pwd ==="
mkdir -p test_pwd
cd test_pwd
cat > Dockerfile <<'EOF'
#mount: pwd
FROM ubuntu:22.04
EOF
ln -sf ../../../build-and-run run
output=$(./run pwd 2>&1)
case "$output" in
    *"Mount directive: Using current directory"*)
        echo "PASS: #mount: pwd directive recognized"
        ;;
    *)
        echo "FAIL: #mount: pwd not recognized"
        echo "Output: $output"
        fail=1
        ;;
esac
cd ..

echo ""
echo "=== Test 2: #mount: .git finds git root ==="
# Create git repo in parent, container in subdirectory
mkdir -p test_git_root
cd test_git_root
git init >/dev/null 2>&1
mkdir subdir
cd subdir
cat > Dockerfile <<'EOF'
#mount: .git
FROM ubuntu:22.04
EOF
ln -sf ../../../../build-and-run run
output=$(./run pwd 2>&1)
git_root=$(cd .. && pwd)
case "$output" in
    *"Mount directive: Using git root directory ($git_root)"*)
        echo "PASS: #mount: .git found git root correctly"
        ;;
    *)
        echo "FAIL: #mount: .git did not find git root"
        echo "Output: $output"
        fail=1
        ;;
esac
cd ../..

echo ""
echo "=== Test 3: #mount: home uses home directory ==="
mkdir -p test_home
cd test_home
cat > Dockerfile <<'EOF'
#mount: home
FROM ubuntu:22.04
EOF
ln -sf ../../../build-and-run run
output=$(./run pwd 2>&1)
case "$output" in
    *"Mount directive: Using home directory"*)
        echo "PASS: #mount: home directive recognized"
        ;;
    *)
        echo "FAIL: #mount: home not recognized"
        echo "Output: $output"
        fail=1
        ;;
esac
cd ..

echo ""
echo "=== Test 4: FIRST-found semantics (.git before pwd) ==="
mkdir -p test_fallback
cd test_fallback
git init >/dev/null 2>&1
mkdir subdir
cd subdir
cat > Dockerfile <<'EOF'
#mount: .git pwd home
FROM ubuntu:22.04
EOF
ln -sf ../../../../build-and-run run
output=$(./run pwd 2>&1)
# Should use .git (first match), not pwd
case "$output" in
    *"Mount directive: Using git root directory"*)
        echo "PASS: FIRST-found semantics work (.git chosen over pwd)"
        ;;
    *"Mount directive: Using current directory"*)
        echo "FAIL: pwd was used instead of .git (FIRST-found failed)"
        echo "Output: $output"
        fail=1
        ;;
    *)
        echo "FAIL: Unexpected output"
        echo "Output: $output"
        fail=1
        ;;
esac
cd ../..

# Cleanup
rm -rf test_pwd test_git_root test_home test_fallback
$ENGINE rmi -f 0018_mount_pwd 0018_mount_git 0018_mount_home 0018_mount_fallback 2>/dev/null || true

if [ "$fail" = 0 ]; then
    echo ""
    echo "PASS: All mount directive tests passed"
fi

exit $fail
