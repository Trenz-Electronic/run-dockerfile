#!/bin/sh
# Test: Automatic rebuild detection with context hash
# Verifies that:
# - Initial build creates hash label
# - Subsequent runs skip rebuild when nothing changed
# - Changes to Dockerfile trigger rebuild
# - Changes to context files trigger rebuild
# - Renaming a file triggers rebuild (filename is part of the hash)
# - Changing a file's mode triggers rebuild (mode is part of the hash)

set -e

. ../lib/engine.sh

fail=0

# Clean up any existing image
$ENGINE rmi -f 0017_auto_rebuild 2>/dev/null || true

# Change to container subdirectory (so test.sh isn't in build context)
cd 0017_auto_rebuild

echo "=== Test 1: First build (image not found) ==="
output=$(./run echo "first build" 2>&1) || true
case "$output" in
    *"not found, rebuilding"*"first build"*)
        echo "PASS: Initial build triggered"
        ;;
    *)
        echo "FAIL: Expected rebuild message not found"
        echo "Output: $output"
        fail=1
        ;;
esac

echo ""
echo "=== Test 2: Verify hash label was stored ==="
hash_label=$($ENGINE inspect --format='{{index .Config.Labels "run-dockerfile.context-hash"}}' 0017_auto_rebuild 2>/dev/null)
hash_length=$(echo "$hash_label" | wc -c)
if [ -n "$hash_label" ] && [ "$hash_length" -eq 65 ]; then
    short_hash=$(echo "$hash_label" | cut -c1-12)
    echo "PASS: Hash label stored (${short_hash}...)"
else
    echo "FAIL: Hash label missing or invalid: '$hash_label' (length: $hash_length)"
    fail=1
fi

echo ""
echo "=== Test 3: Second run with no changes (should skip rebuild) ==="
output=$(./run echo "no rebuild" 2>&1) || true
case "$output" in
    *"rebuilding"*)
        echo "FAIL: Unexpected rebuild when nothing changed"
        echo "Output: $output"
        fail=1
        ;;
    *"no rebuild"*)
        # No 'up-to-date' message expected anymore, just the command output
        echo "PASS: Rebuild skipped when no changes"
        ;;
    *)
        echo "FAIL: Unexpected output"
        echo "Output: $output"
        fail=1
        ;;
esac

echo ""
echo "=== Test 4: Modify Dockerfile (should trigger rebuild) ==="
# Save original Dockerfile
cp Dockerfile Dockerfile.backup
echo "# test comment" >> Dockerfile
output=$(./run echo "after dockerfile change" 2>&1) || true
case "$output" in
    *"changes detected"*"after dockerfile change"*)
        echo "PASS: Dockerfile change triggered rebuild"
        ;;
    *"after dockerfile change"*)
        if ! echo "$output" | grep -q "rebuilding\|changes detected"; then
            echo "FAIL: Change not detected, rebuild was skipped"
            echo "Output: $output"
            fail=1
        fi
        ;;
    *)
        echo "FAIL: Expected rebuild message not found"
        echo "Output: $output"
        fail=1
        ;;
esac

# Restore original Dockerfile
mv Dockerfile.backup Dockerfile

echo ""
echo "=== Test 5: Add context file (should trigger rebuild) ==="
echo "test content" > test_file.txt
output=$(./run echo "after context change" 2>&1) || true
case "$output" in
    *"changes detected"*"after context change"*)
        echo "PASS: Context file change triggered rebuild"
        ;;
    *"after context change"*)
        if ! echo "$output" | grep -q "rebuilding\|changes detected"; then
            echo "FAIL: Context change not detected"
            echo "Output: $output"
            fail=1
        fi
        ;;
    *)
        echo "FAIL: Expected rebuild message not found"
        echo "Output: $output"
        fail=1
        ;;
esac

# Cleanup
rm -f test_file.txt

echo ""
echo "=== Test 6: Rebuild to get new hash after file removed ==="
# After test 5, we removed test_file.txt, so context is different from the current image
# The current image was built with test_file.txt present
# We need to rebuild to match the new context (file removed)
output=$(./run echo "rebuild after removal" 2>&1) || {
    echo "FAIL: rebuild-after-removal run failed"
    echo "Output: $output"
    fail=1
}
# This should rebuild because test_file.txt was removed
echo "Rebuild triggered (expected)"

echo ""
echo "=== Test 7: Verify no further rebuilds ==="
output=$(./run echo "final run" 2>&1) || true
case "$output" in
    *"rebuilding"*)
        echo "FAIL: Unexpected rebuild when context stable"
        echo "Output: $output"
        fail=1
        ;;
    *"final run"*)
        # No 'up-to-date' message expected anymore, just the command output
        echo "PASS: No rebuild when context stable"
        ;;
    *)
        echo "FAIL: Unexpected output"
        echo "Output: $output"
        fail=1
        ;;
esac

echo ""
echo "=== Test 8: Renaming a context file triggers rebuild (filename in hash) ==="
echo "rename-content" > rename_me.txt
./run echo "sync baseline" >/dev/null 2>&1 || true   # rebuild so image matches context
mv rename_me.txt renamed.txt                         # same content, different name
output=$(./run echo "after rename" 2>&1) || {
    echo "FAIL: after-rename run failed"
    echo "Output: $output"
    fail=1
}
if echo "$output" | grep -q "rebuilding\|changes detected"; then
    echo "PASS: Rename triggered rebuild"
else
    echo "FAIL: Rename did not trigger rebuild (filename ignored by hash)"
    echo "Output: $output"
    fail=1
fi
rm -f renamed.txt

echo ""
echo "=== Test 9: Changing a file's mode triggers rebuild (mode in hash) ==="
echo "#!/bin/sh" > mode_test.sh
chmod 644 mode_test.sh
./run echo "sync baseline" >/dev/null 2>&1 || true   # rebuild so image matches context
chmod 755 mode_test.sh                               # mode change only, same content
output=$(./run echo "after chmod" 2>&1) || {
    echo "FAIL: after-chmod run failed"
    echo "Output: $output"
    fail=1
}
if echo "$output" | grep -q "rebuilding\|changes detected"; then
    echo "PASS: chmod triggered rebuild"
else
    echo "FAIL: chmod did not trigger rebuild (mode ignored by hash)"
    echo "Output: $output"
    fail=1
fi
rm -f mode_test.sh

echo ""
echo "=== Test 10: Fallback hash handles filenames with spaces ==="
fakebin="$(pwd)/fake-tar-bin-0017"
mkdir -p "$fakebin"
cat > "$fakebin/gtar" <<'EOF'
#!/bin/sh
exit 1
EOF
cat > "$fakebin/tar" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$fakebin/gtar" "$fakebin/tar"

echo "fallback original" > "fallback space.txt"
PATH="$fakebin:$PATH" ./run echo "fallback baseline" >/dev/null 2>&1 || {
    echo "FAIL: Fallback-hash baseline run failed"
    fail=1
}
echo "fallback changed" > "fallback space.txt"
output=$(PATH="$fakebin:$PATH" ./run echo "after fallback space change" 2>&1) || {
    echo "FAIL: Fallback-hash changed run failed"
    echo "Output: $output"
    fail=1
}
if echo "$output" | grep -q "rebuilding\|changes detected"; then
    echo "PASS: Fallback hash detected change to spaced filename"
else
    echo "FAIL: Fallback hash missed change to spaced filename"
    echo "Output: $output"
    fail=1
fi
rm -rf "$fakebin" "fallback space.txt"

echo ""
echo "=== Test 11: Fallback hash detects rename, mode, and symlink target changes ==="
fakebin="$(pwd)/fake-tar-bin-0017"
mkdir -p "$fakebin"
cat > "$fakebin/gtar" <<'EOF'
#!/bin/sh
exit 1
EOF
cat > "$fakebin/tar" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$fakebin/gtar" "$fakebin/tar"

echo "fallback rename" > fallback_rename_a.txt
PATH="$fakebin:$PATH" ./run echo "fallback rename baseline" >/dev/null 2>&1 || {
    echo "FAIL: Fallback rename baseline run failed"
    fail=1
}
mv fallback_rename_a.txt fallback_rename_b.txt
output=$(PATH="$fakebin:$PATH" ./run echo "after fallback rename" 2>&1) || {
    echo "FAIL: Fallback rename run failed"
    echo "Output: $output"
    fail=1
}
if echo "$output" | grep -q "rebuilding\|changes detected"; then
    echo "PASS: Fallback hash detected rename"
else
    echo "FAIL: Fallback hash missed rename"
    echo "Output: $output"
    fail=1
fi
rm -f fallback_rename_b.txt

echo "#!/bin/sh" > fallback_mode.sh
chmod 644 fallback_mode.sh
PATH="$fakebin:$PATH" ./run echo "fallback mode baseline" >/dev/null 2>&1 || {
    echo "FAIL: Fallback mode baseline run failed"
    fail=1
}
chmod 755 fallback_mode.sh
output=$(PATH="$fakebin:$PATH" ./run echo "after fallback chmod" 2>&1) || {
    echo "FAIL: Fallback chmod run failed"
    echo "Output: $output"
    fail=1
}
if echo "$output" | grep -q "rebuilding\|changes detected"; then
    echo "PASS: Fallback hash detected chmod"
else
    echo "FAIL: Fallback hash missed chmod"
    echo "Output: $output"
    fail=1
fi
rm -f fallback_mode.sh

echo "target a" > target-a
echo "target b" > target-b
ln -s target-a fallback_link
PATH="$fakebin:$PATH" ./run echo "fallback symlink baseline" >/dev/null 2>&1 || {
    echo "FAIL: Fallback symlink baseline run failed"
    fail=1
}
rm -f fallback_link
ln -s target-b fallback_link
output=$(PATH="$fakebin:$PATH" ./run echo "after fallback symlink" 2>&1) || {
    echo "FAIL: Fallback symlink run failed"
    echo "Output: $output"
    fail=1
}
if echo "$output" | grep -q "rebuilding\|changes detected"; then
    echo "PASS: Fallback hash detected symlink target change"
else
    echo "FAIL: Fallback hash missed symlink target change"
    echo "Output: $output"
    fail=1
fi
rm -rf "$fakebin" fallback_link target-a target-b

if [ "$fail" = 0 ]; then
    echo ""
    echo "PASS: All automatic rebuild detection tests passed"
fi

exit $fail
