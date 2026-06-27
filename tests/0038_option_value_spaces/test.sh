#!/bin/sh
# Test: each #option: line is one docker option whose value may contain spaces.

set -e

. ../lib/engine.sh

fail=0
mount_dir="/tmp/run-dockerfile option spaces-$$"

cleanup() {
    rm -rf "$mount_dir"
    cat > Dockerfile <<'EOF'
FROM alpine:latest
EOF
    $ENGINE rmi -f 0038_option_value_spaces 2>/dev/null || true
}
trap cleanup EXIT INT TERM

mkdir -p "$mount_dir"
echo "mounted through #option $$" > "$mount_dir/marker"

cat > Dockerfile <<EOF
#option: -e SPACED_VALUE=value with spaces
#option: -v $mount_dir:/option-space:ro
#option: --mount type=bind,source=$mount_dir,target=/option-mount,readonly
FROM alpine:latest
EOF

output=$(./run sh -c 'printf "env=[%s]\nvol=[%s]\nmount=[%s]\n" "$SPACED_VALUE" "$(cat /option-space/marker)" "$(cat /option-mount/marker)"') || {
    echo "FAIL: run with spaced #option values failed"
    fail=1
    output=""
}

case "$output" in
    *"env=[value with spaces]"*) echo "PASS: #option env value with spaces preserved" ;;
    *) echo "FAIL: #option env value with spaces not preserved"; echo "Output: $output"; fail=1 ;;
esac

case "$output" in
    *"vol=[mounted through #option $$]"*) echo "PASS: #option -v value with spaces preserved" ;;
    *) echo "FAIL: #option -v value with spaces not preserved"; echo "Output: $output"; fail=1 ;;
esac

case "$output" in
    *"mount=[mounted through #option $$]"*) echo "PASS: #option --mount value with spaces preserved" ;;
    *) echo "FAIL: #option --mount value with spaces not preserved"; echo "Output: $output"; fail=1 ;;
esac

exit "$fail"
