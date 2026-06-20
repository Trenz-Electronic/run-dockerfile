#!/bin/sh
# Test: value-taking command-line options fail early when their value is missing.

set -e

fail=0

check_missing_value() {
    opt=$1
    status=0
    output=$(./run "$opt" 2>&1) || status=$?

    if [ "$status" -eq 0 ]; then
        echo "FAIL: $opt without a value exited 0"
        fail=1
        return
    fi

    case "$output" in
        *"option '$opt' requires a value"*)
            echo "PASS: $opt without a value fails clearly"
            ;;
        *)
            echo "FAIL: $opt without a value produced unexpected output"
            echo "Output: $output"
            fail=1
            ;;
    esac
}

for opt in -e --env -v --volume -p --cpus -m --name; do
    check_missing_value "$opt"
done

exit "$fail"
