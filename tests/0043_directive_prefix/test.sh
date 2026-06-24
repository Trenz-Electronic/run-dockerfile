#!/bin/sh
# Test: #run-dockerfile: directive prefix.
#  - prefixed directive honored ANYWHERE (including after line 20)
#  - whitespace required after the prefix colon
#  - '#' must be at column 1 (an indented prefixed line is ignored)
#  - an unknown keyword after the prefix is a hard error
#  - the old unprefixed form still works but emits a deprecation WARNING
#  - old and new forms accumulate

set -e

fail=0

filler20() {
    i=1
    while [ "$i" -le 20 ]; do
        printf '# filler %s\n' "$i"
        i=$((i + 1))
    done
}

cleanup() { rm -f Dockerfile err; }
trap cleanup EXIT

# --- Case 1: prefixed directive honored AFTER line 20, no deprecation warning ---
{ filler20; printf '#run-dockerfile: option -e PREFIXVAR=hello\n'; printf 'FROM alpine:latest\n'; } > Dockerfile
if out=$(./run sh -c 'printf "[%s]" "$PREFIXVAR"' 2>err); then
    if printf '%s' "$out" | grep -F '[hello]' >/dev/null; then
        echo "PASS: prefixed option honored after line 20"
    else
        echo "FAIL: prefixed option after line 20 not honored (out=[$out])"; cat err; fail=1
    fi
else
    echo "FAIL: run errored for prefixed option after line 20"; cat err; fail=1
fi
if grep -F 'WARNING: deprecated' err >/dev/null 2>&1; then
    echo "FAIL: prefixed (new) form emitted a deprecation warning"; fail=1
fi

# --- Case 2: old unprefixed form still honored, emits deprecation warning ---
{ printf '#option: -e OLDVAR=legacy\n'; printf 'FROM alpine:latest\n'; } > Dockerfile
if out=$(./run sh -c 'printf "[%s]" "$OLDVAR"' 2>err); then
    if printf '%s' "$out" | grep -F '[legacy]' >/dev/null; then
        echo "PASS: old unprefixed form still honored"
    else
        echo "FAIL: old form not honored (out=[$out])"; cat err; fail=1
    fi
else
    echo "FAIL: run errored for old form"; cat err; fail=1
fi
if grep -F 'WARNING: deprecated' err >/dev/null 2>&1; then
    echo "PASS: old form emitted a deprecation warning"
else
    echo "FAIL: old form did NOT emit a deprecation warning"; cat err; fail=1
fi

# --- Case 3: whitespace required after the prefix colon ---
{ printf '#run-dockerfile:option -e X=y\n'; printf 'FROM alpine:latest\n'; } > Dockerfile
if ./run true >/dev/null 2>err; then
    echo "FAIL: missing whitespace after prefix was accepted"; fail=1
else
    if grep -F 'line 1' err >/dev/null 2>&1; then
        echo "PASS: missing whitespace after prefix is an error"
    else
        echo "FAIL: missing-whitespace error lacked a line number"; cat err; fail=1
    fi
fi

# --- Case 4: '#' must be at column 1 (an indented prefixed line is ignored) ---
{ printf '   #run-dockerfile: option -e INDENTVAR=nope\n'; printf 'FROM alpine:latest\n'; } > Dockerfile
if out=$(./run sh -c 'printf "[%s]" "$INDENTVAR"' 2>err); then
    if printf '%s' "$out" | grep -F 'nope' >/dev/null; then
        echo "FAIL: indented prefixed directive was honored"; fail=1
    else
        echo "PASS: indented prefixed directive ignored (not column 1)"
    fi
else
    echo "FAIL: run errored on an indented prefixed (comment) line"; cat err; fail=1
fi

# --- Case 5: an unknown keyword after the prefix is a hard error ---
{ printf '#run-dockerfile: bogus whatever\n'; printf 'FROM alpine:latest\n'; } > Dockerfile
if ./run true >/dev/null 2>err; then
    echo "FAIL: unknown prefixed keyword was accepted"; fail=1
else
    if grep -F 'bogus' err >/dev/null 2>&1; then
        echo "PASS: unknown prefixed keyword is an error"
    else
        echo "FAIL: unknown-keyword error did not mention the keyword"; cat err; fail=1
    fi
fi

# --- Case 6: old and new forms accumulate ---
{ printf '#option: -e OLDACC=one\n'; filler20; printf '#run-dockerfile: option -e NEWACC=two\n'; printf 'FROM alpine:latest\n'; } > Dockerfile
if out=$(./run sh -c 'printf "[%s][%s]" "$OLDACC" "$NEWACC"' 2>err); then
    if printf '%s' "$out" | grep -F '[one][two]' >/dev/null; then
        echo "PASS: old and new forms accumulate"
    else
        echo "FAIL: forms did not accumulate (out=[$out])"; cat err; fail=1
    fi
else
    echo "FAIL: run errored for accumulation case"; cat err; fail=1
fi

exit $fail
