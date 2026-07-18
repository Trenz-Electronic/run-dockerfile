#!/bin/sh
# Test: the inherit form `#option: -e VAR` (no =value) adds VAR to the ENV
# preservation list, just like the command-line `-e VAR` form already did. This
# is what the README X11 example relies on (`#option: -e DISPLAY`).
#
# Regression test for the fix that replaced the value-only ("=" required)
# #option env-name regex with token-array parsing. The decisive check is the
# variable that is UNSET on the host: with the fix its name is collected, so the
# container re-asserts it as a defined (empty) variable via `env VAR=`; under the
# old regex the name was dropped and the variable stayed unset. This discriminator
# does not depend on whether `su` happens to preserve environment variables.

set -e

fail=0

# 1. Inherit form carries the host value through to the command.
export DB_INHERIT_VALUE=carried_through
output=$(./run sh -c 'echo "value=[$DB_INHERIT_VALUE]"') || true
case "$output" in
    *"value=[carried_through]"*) echo "PASS: inherit-form -e VAR carries the host value" ;;
    *) echo "FAIL: inherit-form value not carried - got: $output"; fail=1 ;;
esac

# 2. Inherit form is added to the preserve list even when the variable is unset on
#    the host: the container defines it (empty). Old code left it unset.
output=$(env -u DB_INHERIT_UNSET ./run sh -c 'echo "set=[${DB_INHERIT_UNSET+SET}]"') || true
case "$output" in
    *"set=[SET]"*) echo "PASS: inherit-form -e VAR added to preserve list (defined even when unset on host)" ;;
    *) echo "FAIL: inherit-form -e VAR not preserved - got: $output"; fail=1 ;;
esac

# 3. Sanity: a variable never declared via #option stays unset (so check 2 is
#    proving the directive's effect, not some blanket behavior).
output=$(./run sh -c 'echo "undeclared=[${DB_NOT_DECLARED+SET}]"') || true
case "$output" in
    *"undeclared=[]"*) echo "PASS: undeclared variable stays unset" ;;
    *) echo "FAIL: undeclared variable unexpectedly set - got: $output"; fail=1 ;;
esac

exit $fail
