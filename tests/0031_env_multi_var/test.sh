#!/bin/sh
# Test: every variable on a multi-variable ENV line is preserved across su,
# not just the first one. The preservation contract is the DOCKER_PRESERVE_ENV
# list the host half computes and the container half re-injects.

set -e

output=$(./run sh -c 'echo "PRESERVE=[$DOCKER_PRESERVE_ENV]"; echo "VALS=$ALPHA|$BETA|$GAMMA|$DELTA"')

fail=0
for name in ALPHA BETA GAMMA DELTA; do
    case "$output" in
        *"$name"*) ;;
        *)
            echo "FAIL: $name missing from DOCKER_PRESERVE_ENV"
            fail=1
            ;;
    esac
done

# Sanity: the values themselves survive into the user's command.
case "$output" in
    *"VALS=one|two|three|four"*) ;;
    *)
        echo "FAIL: expected VALS=one|two|three|four"
        fail=1
        ;;
esac

if [ "$fail" -ne 0 ]; then
    echo "Got: $output"
    exit 1
fi

echo "PASS: all ENV vars from a multi-variable ENV line are preserved"
exit 0
