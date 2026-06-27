#!/bin/sh
# Test: a glob character in an #option: value is passed literally and never
# expanded against the host filesystem during parsing of the directive.

set -e

. ../lib/engine.sh

fail=0

cleanup() {
    rm -f match.txt other.txt
    $ENGINE rmi -f 0023_glob_in_option 2>/dev/null || true
}
trap cleanup EXIT

# Decoy files that *.txt would match if the value were globbed during parsing.
echo decoy > match.txt
echo decoy > other.txt

# Dockerfile sets: #option: -e PATTERN=*.txt
# $PATTERN must be the literal "*.txt", not "match.txt other.txt".
output=$(./run sh -c 'printf %s "$PATTERN"')
if [ "$output" = "*.txt" ]; then
    echo "PASS: glob char in #option value passed literally"
else
    echo "FAIL: expected '*.txt', got: '$output'"
    fail=1
fi

exit $fail
