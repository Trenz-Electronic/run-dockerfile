#!/bin/sh
# Test: host-side help exits successfully and does not require Docker.

set -e

check_help() {
    opt=$1
    status=0
    output=$(./run "$opt" 2>&1) || status=$?

    if [ "$status" -ne 0 ]; then
        echo "FAIL: ./run $opt exited $status"
        echo "Output: $output"
        return 1
    fi

    for expected in \
        "Usage:" \
        "Supported command-line options" \
        "Dockerfile directives" \
        "#http.static:"
    do
        if ! echo "$output" | grep -F "$expected" >/dev/null; then
            echo "FAIL: ./run $opt output missing '$expected'"
            echo "Output: $output"
            return 1
        fi
    done

    echo "PASS: ./run $opt prints usage"
}

check_help --help
check_help -h
