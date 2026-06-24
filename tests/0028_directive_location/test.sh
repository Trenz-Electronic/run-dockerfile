#!/bin/sh
# Test: run-dockerfile directives after line 20 fail loudly.

set -e

fail=0

write_late_directive_dockerfile() {
    directive="$1"
    i=1
    : > Dockerfile
    while [ "$i" -le 20 ]; do
        printf '# filler %s\n' "$i" >> Dockerfile
        i=$((i + 1))
    done
    printf '%s\n' "$directive" >> Dockerfile
    printf 'FROM alpine:latest\n' >> Dockerfile
}

check_late_directive() {
    directive="$1"
    expected="$2"

    write_late_directive_dockerfile "$directive"

    if output=$(./run true 2>&1); then
        echo "FAIL: $directive was accepted after line 20"
        fail=1
        return
    fi

    if printf '%s\n' "$output" | grep -F "line 21" >/dev/null &&
       printf '%s\n' "$output" | grep -F "$expected" >/dev/null &&
       printf '%s\n' "$output" | grep -F "first 20 lines" >/dev/null; then
        echo "PASS: $expected rejected after line 20"
    else
        echo "FAIL: unexpected error for $directive"
        echo "Output: $output"
        fail=1
    fi
}

check_late_directive '# platform: arm64' '#platform:'
check_late_directive '#mount: .git' '#mount:'
check_late_directive '#copy.home: .license.dat' '#copy.home:'
check_late_directive '#usermount: $HOME/.cache/tool' '#usermount:'
check_late_directive '#context: installer=../installers' '#context:'
check_late_directive '#http.static: INSTALLER=../installers' '#http.static:'
check_late_directive '#option: --read-only' '#option:'
check_late_directive '#sudo: all' '#sudo:'

# The prefixed form is honored anywhere, including after line 20: it must NOT
# trip the unprefixed-only 20-line limit.
write_late_directive_dockerfile '#run-dockerfile: option -e LATE_PREFIX_OK=1'
if ./run true >/dev/null 2>err; then
    if printf '%s\n' "$(cat err)" | grep -F "first 20 lines" >/dev/null; then
        echo "FAIL: prefixed directive after line 20 hit the 20-line limit"
        cat err
        fail=1
    else
        echo "PASS: prefixed directive after line 20 is honored"
    fi
else
    echo "FAIL: prefixed directive after line 20 caused run to fail"
    cat err
    fail=1
fi

rm -f Dockerfile err

exit $fail
