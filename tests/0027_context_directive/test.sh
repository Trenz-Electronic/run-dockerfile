#!/bin/sh
# Test: #context: maps to BuildKit named contexts.

set -e

fail=0
test_dir="$(cd "$(dirname "$0")" && pwd)"
container_dir="0027_context_directive"
cd "$test_dir"

cleanup_generated() {
    rm -rf "extra context" "$container_dir" Dockerfile
}

cleanup_generated
docker rmi -f 0027_context_directive 2>/dev/null || true
mkdir -p "$container_dir"
ln -sf ../../../build-and-run "$container_dir/run"

echo "=== Test 1: Local relative named context with a space in the path ==="
mkdir -p "extra context"
echo "named-context-original-$$" > "extra context/marker.txt"
cat > "$container_dir/Dockerfile" <<'EOF'
#context: extra=../extra context
FROM alpine:latest
COPY --from=extra marker.txt /tmp/context-marker.txt
EOF

output=$(cd "$container_dir" && ./run cat /tmp/context-marker.txt) || {
    echo "FAIL: Build or run failed for local named context"
    fail=1
}
if [ "$output" = "named-context-original-$$" ]; then
    echo "PASS: Local named context copied expected content"
else
    echo "FAIL: Local named context content mismatch: '$output'"
    fail=1
fi

echo ""
echo "=== Test 2: Named context contents do not trigger auto-rebuild ==="
echo "named-context-changed-$$" > "extra context/marker.txt"
output=$(cd "$container_dir" && ./run cat /tmp/context-marker.txt) || {
    echo "FAIL: Second run failed"
    fail=1
}
if [ "$output" = "named-context-original-$$" ]; then
    echo "PASS: Changed named-context file did not trigger rebuild"
else
    echo "FAIL: Expected stale content after skipped rebuild, got: '$output'"
    fail=1
fi

echo ""
echo "=== Test 3: Forced rebuild picks up changed named-context content ==="
docker rmi -f 0027_context_directive >/dev/null 2>&1 || true
output=$(cd "$container_dir" && ./run cat /tmp/context-marker.txt) || {
    echo "FAIL: Forced rebuild failed"
    fail=1
}
if [ "$output" = "named-context-changed-$$" ]; then
    echo "PASS: Forced rebuild picked up changed named-context content"
else
    echo "FAIL: Expected changed content after forced rebuild, got: '$output'"
    fail=1
fi

echo ""
echo "=== Test 4: Missing local named context path fails clearly ==="
docker rmi -f 0027_context_directive >/dev/null 2>&1 || true
cat > "$container_dir/Dockerfile" <<'EOF'
#context: missing=missing-context-dir
FROM alpine:latest
RUN true
EOF
if output=$(cd "$container_dir" && ./run true 2>&1); then
    echo "FAIL: Missing local context path unexpectedly succeeded"
    fail=1
else
    case "$output" in
        *"ERROR: #context: local path does not exist for missing:"*"missing-context-dir"*)
            echo "PASS: Missing local context path failed clearly"
            ;;
        *)
            echo "FAIL: Missing local context path error was unclear"
            echo "Output: $output"
            fail=1
            ;;
    esac
fi

echo ""
echo "=== Test 5: Pass-through docker-image named context value ==="
docker rmi -f 0027_context_directive >/dev/null 2>&1 || true
cat > "$container_dir/Dockerfile" <<'EOF'
#context: base=docker-image://alpine:latest
FROM alpine:latest
COPY --from=base /etc/alpine-release /tmp/base-release
EOF
output=$(cd "$container_dir" && ./run sh -c 'test -s /tmp/base-release && cat /tmp/base-release') || {
    echo "FAIL: Pass-through docker-image named context failed"
    fail=1
}
if [ -n "$output" ]; then
    echo "PASS: Pass-through docker-image named context copied base file"
else
    echo "FAIL: Pass-through docker-image named context produced empty output"
    fail=1
fi

echo ""
echo "=== Test 6: Invalid context name fails before docker build ==="
docker rmi -f 0027_context_directive >/dev/null 2>&1 || true
cat > "$container_dir/Dockerfile" <<'EOF'
#context: BAD=../extra context
FROM alpine:latest
RUN true
EOF
if output=$(cd "$container_dir" && ./run true 2>&1); then
    echo "FAIL: Invalid context name unexpectedly succeeded"
    fail=1
else
    case "$output" in
        *"ERROR: invalid #context: name 'BAD'"*)
            echo "PASS: Invalid context name failed clearly"
            ;;
        *)
            echo "FAIL: Invalid context name error was unclear"
            echo "Output: $output"
            fail=1
            ;;
    esac
fi

cleanup_generated

if [ "$fail" = 0 ]; then
    echo ""
    echo "PASS: All #context: directive tests passed"
fi

exit "$fail"
