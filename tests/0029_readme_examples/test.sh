#!/bin/sh
# Test: README Quick Start examples stay executable and internally consistent.

set -e

fail=0
test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$test_dir/../.." && pwd)"
readme="$repo_root/README.md"
workspace="${TMPDIR:-/tmp}/docker-booster-readme-$$"
project="$workspace/project"

cleanup() {
    docker rmi -f my-container >/dev/null 2>&1 || true
    rm -rf "$workspace"
}
trap cleanup EXIT INT TERM

extract_sample() {
    sample_id="$1"
    awk -v sample_id="$sample_id" '
        $0 ~ "^[[:space:]]*<!--[[:space:]]*readme-sample: " sample_id "[[:space:]]*-->[[:space:]]*$" {
            found = 1
            next
        }
        found && /^[[:space:]]*```/ {
            if (in_block) {
                exit
            }
            in_block = 1
            next
        }
        found && in_block {
            sub(/^   /, "")
            print
        }
    ' "$readme"
}

write_sample_script() {
    sample_id="$1"
    script_path="$2"
    extract_sample "$sample_id" > "$script_path"
    if [ ! -s "$script_path" ]; then
        echo "FAIL: README sample '$sample_id' was not found or was empty"
        fail=1
    fi
}

assert_readme_contains() {
    expected="$1"
    if grep -F "$expected" "$readme" >/dev/null; then
        echo "PASS: README contains expected text: $expected"
    else
        echo "FAIL: README missing expected text: $expected"
        fail=1
    fi
}

assert_readme_not_contains() {
    unexpected="$1"
    if grep -F "$unexpected" "$readme" >/dev/null; then
        echo "FAIL: README contains unexpected text: $unexpected"
        fail=1
    else
        echo "PASS: README does not contain: $unexpected"
    fi
}

mkdir -p "$project"

echo "=== Extract Quick Start samples ==="
write_sample_script quickstart-01-create-container "$workspace/quickstart-01.sh"
write_sample_script quickstart-03-create-run-symlink "$workspace/quickstart-03.sh"
write_sample_script quickstart-04-run-commands "$workspace/quickstart-04.sh"

if [ "$fail" -ne 0 ]; then
    exit "$fail"
fi

echo ""
echo "=== Run Quick Start setup sample ==="
(cd "$project" && sh "$workspace/quickstart-01.sh") || {
    echo "FAIL: Quick Start container/Makefile setup sample failed"
    fail=1
}

from_line=$(sed -n 's/^[[:space:]]*\(FROM .*\)$/\1/p' "$project/containers/my-container/Dockerfile" | head -n1)
if [ "$from_line" = "FROM buildpack-deps:bookworm" ]; then
    echo "PASS: Quick Start Dockerfile uses tested buildpack-deps base image"
else
    echo "FAIL: unexpected Quick Start FROM line: '$from_line'"
    fail=1
fi

if [ -f "$project/Makefile" ]; then
    echo "PASS: Quick Start Makefile was created"
else
    echo "FAIL: Quick Start Makefile was not created"
    fail=1
fi

echo ""
echo "=== Substitute local docker-booster checkout for README submodule command ==="
submodule_sample=$(extract_sample quickstart-02-add-docker-booster)
booster_dir=$(printf '%s\n' "$submodule_sample" | awk '/git submodule add / {print $NF; exit}')
if [ "$booster_dir" = "docker-booster" ]; then
    ln -s "$repo_root" "$project/$booster_dir"
    echo "PASS: substituted local docker-booster symlink for submodule destination"
else
    echo "FAIL: could not determine docker-booster destination from README submodule sample: '$submodule_sample'"
    fail=1
fi

echo ""
echo "=== Run Quick Start symlink sample ==="
(cd "$project" && sh "$workspace/quickstart-03.sh") || {
    echo "FAIL: Quick Start run symlink sample failed"
    fail=1
}
if [ -L "$project/containers/my-container/run" ]; then
    echo "PASS: run symlink was created"
else
    echo "FAIL: run symlink was not created"
    fail=1
fi

echo ""
echo "=== Run Quick Start command sample ==="
(cd "$project" && sh "$workspace/quickstart-04.sh") || {
    echo "FAIL: Quick Start run command sample failed"
    fail=1
}

echo ""
echo "=== Static README checks for known shell-example pitfalls ==="
assert_readme_contains "(cd containers/my-container && ln -s ../../docker-booster/build-and-run run)"
assert_readme_contains "./containers/my-container/run sh -lc 'make -j\$(nproc)'"
assert_readme_not_contains "./containers/my-container/run make -j\$(nproc)"

if [ "$fail" = 0 ]; then
    echo ""
    echo "PASS: README Quick Start examples passed"
fi

exit "$fail"
