#!/bin/sh
# caps: python3
# Test: README Quick Start examples stay executable and internally consistent.

set -e

. ../lib/engine.sh

fail=0
test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$test_dir/../.." && pwd)"
readme="$repo_root/README.md"
workspace="${TMPDIR:-/tmp}/run-dockerfile-readme-$$"
project="$workspace/project"
original_home="$HOME"

cleanup() {
    $ENGINE rmi -f my-container readme-option readme-option-spaces readme-mount \
        readme-copy-home readme-usermount-env readme-usermount-multiple \
        readme-http-static readme-context-local readme-sudo readme-tz-alpine \
        readme-tz-locale-debian readme-tz-locale-debian-regional \
        readme-tz-locale-host readme-installer-expect >/dev/null 2>&1 || true
    # Empty host dir created for the spaced-path #option: sample; rmdir is
    # safe because the sample only reads the mount, so it stays empty.
    rmdir "/tmp/my cache" 2>/dev/null || true
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

write_sample_file() {
    sample_id="$1"
    file_path="$2"
    extract_sample "$sample_id" > "$file_path"
    if [ ! -s "$file_path" ]; then
        echo "FAIL: README sample '$sample_id' was not found or was empty"
        fail=1
    fi
}

prepare_container_from_sample() {
    sample_id="$1"
    container_name="$2"
    container_dir="$project/containers/$container_name"

    mkdir -p "$container_dir"
    write_sample_file "$sample_id" "$container_dir/Dockerfile"
    ln -sf ../../run-dockerfile/build-and-run "$container_dir/run"
}

prepare_basic_container() {
    container_name="$1"
    container_dir="$project/containers/$container_name"

    mkdir -p "$container_dir"
    cat > "$container_dir/Dockerfile" <<'EOF'
FROM buildpack-deps:bookworm
EOF
    ln -sf ../../run-dockerfile/build-and-run "$container_dir/run"
}

assert_sample_uses_prefix() {
    sample_id="$1"
    tmp_file="$workspace/${sample_id}.Dockerfile"

    write_sample_file "$sample_id" "$tmp_file"
    # The prefixed form is the documented, recommended syntax: every directive
    # sample must use it, and none may show a deprecated unprefixed directive.
    if ! grep -qE '^#run-dockerfile: ' "$tmp_file"; then
        echo "FAIL: README sample '$sample_id' does not use the #run-dockerfile: prefix"
        fail=1
        return
    fi
    if grep -qE '^#[[:space:]]*(platform|mount|copy\.home|usermount|context|http\.static|option|sudo):' "$tmp_file"; then
        echo "FAIL: README sample '$sample_id' still shows a deprecated unprefixed directive"
        fail=1
        return
    fi
    echo "PASS: README sample '$sample_id' uses the #run-dockerfile: prefix"
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
echo "=== Substitute local run-dockerfile checkout for README submodule command ==="
submodule_sample=$(extract_sample quickstart-02-add-run-dockerfile)
booster_dir=$(printf '%s\n' "$submodule_sample" | awk '/git submodule add / {print $NF; exit}')
if [ "$booster_dir" = "run-dockerfile" ]; then
    ln -s "$repo_root" "$project/$booster_dir"
    echo "PASS: substituted local run-dockerfile symlink for submodule destination"
else
    echo "FAIL: could not determine run-dockerfile destination from README submodule sample: '$submodule_sample'"
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
assert_readme_contains "(cd containers/my-container && ln -s ../../run-dockerfile/build-and-run run)"
assert_readme_contains "./containers/my-container/run sh -lc 'make -j\$(nproc)'"
assert_readme_not_contains "./containers/my-container/run make -j\$(nproc)"

echo ""
echo "=== Run command-line option sample ==="
# Reuses the my-container image already built by the Quick Start samples above;
# prepare_basic_container is idempotent (identical Dockerfile, so no rebuild).
prepare_basic_container my-container
write_sample_script options-01-command-line "$workspace/options-01.sh"
(cd "$project" && sh "$workspace/options-01.sh") || {
    echo "FAIL: command-line options README sample failed"
    fail=1
}

echo ""
echo "=== Run Dockerfile directive samples ==="
(cd "$project" && git init >/dev/null 2>&1) || true
project_real=$(cd "$project" && pwd)

prepare_container_from_sample directive-01-option readme-option
(cd "$project" && ./containers/readme-option/run true) || {
    echo "FAIL: #option: README sample failed"
    fail=1
}

# The spaced-value #option: sample bind-mounts /tmp/my cache (a path with a
# space) via both -v and --mount, and sets -e TOOL_FLAGS=--mode fast. The
# --mount source must already exist, so create it first.
mkdir -p "/tmp/my cache"
prepare_container_from_sample directive-01b-option-spaces readme-option-spaces
output=$(cd "$project" && ./containers/readme-option-spaces/run sh -lc 'test "$TOOL_FLAGS" = "--mode fast" && test -d /cache && test -d /cache-ro && echo OPTION_SPACES_OK') || {
    echo "FAIL: #option: spaced-value README sample failed"
    fail=1
    output=""
}
if echo "$output" | grep -F "OPTION_SPACES_OK" >/dev/null; then
    echo "PASS: #option: spaced-value README sample preserved spaced option values"
else
    echo "FAIL: #option: spaced-value README sample did not preserve spaced option values"
    echo "Output: $output"
    fail=1
fi

prepare_container_from_sample directive-02-mount readme-mount
output=$(cd "$project" && RUN_DOCKERFILE_VERBOSE=1 ./containers/readme-mount/run pwd 2>&1) || {
    echo "FAIL: #mount: README sample failed"
    fail=1
    output=""
}
if echo "$output" | grep -F "Mount directive: Using git root directory ($project_real)" >/dev/null; then
    echo "PASS: #mount: README sample mounted git root"
else
    echo "FAIL: #mount: README sample did not mount git root"
    echo "Output: $output"
    fail=1
fi

home_dir="$workspace/home"
mkdir -p "$home_dir/.config/my-tool"
echo "license from README test" > "$home_dir/.license.dat"
echo "config from README test" > "$home_dir/.config/my-tool/license.json"
prepare_container_from_sample directive-03-copy-home readme-copy-home
output=$(cd "$project" && HOME="$home_dir" DOCKER_CONFIG="$original_home/.docker" ./containers/readme-copy-home/run sh -lc 'cat ~/.license.dat && cat ~/.config/my-tool/license.json') || {
    echo "FAIL: #copy.home: README sample failed"
    fail=1
    output=""
}
if echo "$output" | grep -F "license from README test" >/dev/null &&
   echo "$output" | grep -F "config from README test" >/dev/null; then
    echo "PASS: #copy.home: README sample copied both files"
else
    echo "FAIL: #copy.home: README sample did not copy expected files"
    echo "Output: $output"
    fail=1
fi

prepare_container_from_sample directive-04-usermount-env readme-usermount-env
output=$(cd "$project" && HOME="$home_dir" DOCKER_CONFIG="$original_home/.docker" ./containers/readme-usermount-env/run sh -lc 'test -d "$HOME/projects/shared-cache" && test -d "$HOME/.local/share/myapp" && echo USERMOUNT_ENV_OK') || {
    echo "FAIL: #usermount: env README sample failed"
    fail=1
    output=""
}
if echo "$output" | grep -F "USERMOUNT_ENV_OK" >/dev/null; then
    echo "PASS: #usermount: env README sample mounted expected directories"
else
    echo "FAIL: #usermount: env README sample did not mount expected directories"
    echo "Output: $output"
    fail=1
fi

prepare_container_from_sample directive-05-usermount-multiple readme-usermount-multiple
output=$(cd "$project" && HOME="$home_dir" DOCKER_CONFIG="$original_home/.docker" ./containers/readme-usermount-multiple/run sh -lc 'test -d "$HOME/.cache/pip" && test -d "$HOME/.cache/npm" && echo USERMOUNT_MULTI_OK') || {
    echo "FAIL: #usermount: multiple README sample failed"
    fail=1
    output=""
}
if echo "$output" | grep -F "USERMOUNT_MULTI_OK" >/dev/null; then
    echo "PASS: #usermount: multiple README sample mounted expected directories"
else
    echo "FAIL: #usermount: multiple README sample did not mount expected directories"
    echo "Output: $output"
    fail=1
fi

mkdir -p "$project/containers/installers"
cat > "$project/containers/installers/large-sdk-installer.run" <<'EOF'
#!/bin/sh
echo "http static installer ran" > /tmp/http-static-marker
EOF
prepare_container_from_sample directive-07-http-static readme-http-static
output=$(cd "$project" && ./containers/readme-http-static/run cat /tmp/http-static-marker) || {
    echo "FAIL: #http.static: README sample failed"
    fail=1
    output=""
}
if [ "$output" = "http static installer ran" ]; then
    echo "PASS: #http.static: README sample consumed served installer"
else
    echo "FAIL: #http.static: README sample produced unexpected output: '$output'"
    fail=1
fi

prepare_container_from_sample directive-08-context-local readme-context-local
output=$(cd "$project" && ./containers/readme-context-local/run cat /tmp/http-static-marker) || {
    echo "FAIL: local #context: README sample failed"
    fail=1
    output=""
}
if echo "$output" | grep -F "http static installer ran" >/dev/null; then
    echo "PASS: local #context: README sample copied and ran installer"
else
    echo "FAIL: local #context: README sample did not run installer"
    echo "Output: $output"
    fail=1
fi

prepare_container_from_sample directive-10-sudo readme-sudo
output=$(cd "$project" && ./containers/readme-sudo/run sudo id -u) || {
    echo "FAIL: #sudo: README sample failed"
    fail=1
    output=""
}
if [ "$output" = "0" ]; then
    echo "PASS: #sudo: README sample configured passwordless sudo"
else
    echo "FAIL: #sudo: README sample returned unexpected output: '$output'"
    fail=1
fi

echo ""
echo "=== Run timezone and locale README samples ==="
prepare_container_from_sample timezone-01-alpine-fixed readme-tz-alpine
output=$(cd "$project" && ./containers/readme-tz-alpine/run sh -lc 'printf "%s\n" "$TZ"; date +%z') || {
    echo "FAIL: Alpine timezone README sample failed"
    fail=1
    output=""
}
if echo "$output" | grep -Fx "Etc/UTC" >/dev/null &&
   echo "$output" | grep -Fx "+0000" >/dev/null; then
    echo "PASS: Alpine timezone README sample set UTC"
else
    echo "FAIL: Alpine timezone README sample did not set UTC"
    echo "Output: $output"
    fail=1
fi

prepare_container_from_sample timezone-02-debian-fixed readme-tz-locale-debian
output=$(cd "$project" && ./containers/readme-tz-locale-debian/run sh -lc 'printf "%s\n" "$TZ"; printf "%s\n" "$LANG"; date +%z') || {
    echo "FAIL: Debian/Ubuntu timezone and locale README sample failed"
    fail=1
    output=""
}
if echo "$output" | grep -Fx "Etc/UTC" >/dev/null &&
   echo "$output" | grep -Fx "C.UTF-8" >/dev/null &&
   echo "$output" | grep -Fx "+0000" >/dev/null; then
    echo "PASS: Debian/Ubuntu timezone and locale README sample set UTC and C.UTF-8"
else
    echo "FAIL: Debian/Ubuntu timezone and locale README sample did not set expected values"
    echo "Output: $output"
    fail=1
fi

prepare_container_from_sample timezone-03-debian-regional-locale readme-tz-locale-debian-regional
output=$(cd "$project" && ./containers/readme-tz-locale-debian-regional/run sh -lc 'printf "%s\n" "$LANG"; printf "%s\n" "$LC_ALL"; locale -a | grep -Fx de_DE.utf8') || {
    echo "FAIL: Debian/Ubuntu regional locale README sample failed"
    fail=1
    output=""
}
if echo "$output" | grep -Fx "de_DE.UTF-8" >/dev/null &&
   echo "$output" | grep -Fx "de_DE.utf8" >/dev/null; then
    echo "PASS: Debian/Ubuntu regional locale README sample generated de_DE.UTF-8"
else
    echo "FAIL: Debian/Ubuntu regional locale README sample did not produce expected locale values"
    echo "Output: $output"
    fail=1
fi

prepare_container_from_sample timezone-04-host-env-dockerfile readme-tz-locale-host
output=$(cd "$project" && TZ=Etc/UTC LANG=C.UTF-8 ./containers/readme-tz-locale-host/run sh -lc 'printf "%s %s\n" "$TZ" "$LANG"') || {
    echo "FAIL: host-provided timezone and locale Dockerfile README sample failed"
    fail=1
    output=""
}
if [ "$output" = "Etc/UTC C.UTF-8" ]; then
    echo "PASS: host-provided timezone and locale Dockerfile README sample forwarded values"
else
    echo "FAIL: host-provided timezone and locale Dockerfile README sample produced unexpected output: '$output'"
    fail=1
fi

prepare_basic_container my-container
write_sample_script timezone-05-command-fixed "$workspace/timezone-05-command-fixed.sh"
output=$(cd "$project" && sh "$workspace/timezone-05-command-fixed.sh") || {
    echo "FAIL: fixed command-line timezone and locale README sample failed"
    fail=1
    output=""
}
if echo "$output" | grep -Fx "+0000" >/dev/null &&
   echo "$output" | grep -Fx "C.UTF-8" >/dev/null; then
    echo "PASS: fixed command-line timezone and locale README sample produced expected values"
else
    echo "FAIL: fixed command-line timezone and locale README sample produced unexpected output"
    echo "Output: $output"
    fail=1
fi

write_sample_script timezone-06-command-host-env "$workspace/timezone-06-command-host-env.sh"
output=$(cd "$project" && sh "$workspace/timezone-06-command-host-env.sh") || {
    echo "FAIL: host-env command-line timezone and locale README sample failed"
    fail=1
    output=""
}
if [ "$output" = "Etc/UTC C.UTF-8" ]; then
    echo "PASS: host-env command-line timezone and locale README sample forwarded values"
else
    echo "FAIL: host-env command-line timezone and locale README sample produced unexpected output: '$output'"
    fail=1
fi

write_sample_script timezone-07-command-localtime "$workspace/timezone-07-command-localtime.sh"
if [ -e /etc/localtime ]; then
    output=$(cd "$project" && sh "$workspace/timezone-07-command-localtime.sh") || {
        echo "FAIL: /etc/localtime command-line README sample failed"
        fail=1
        output=""
    }
    if echo "$output" | grep -E '^[+-][0-9]{4}$' >/dev/null; then
        echo "PASS: /etc/localtime command-line README sample produced a timezone offset"
    else
        echo "FAIL: /etc/localtime command-line README sample produced unexpected output: '$output'"
        fail=1
    fi
else
    echo "SKIP: /etc/localtime command-line README sample requires host /etc/localtime"
fi

echo ""
echo "=== Run non-interactive installer (expect) README sample ==="
case "$ENGINE" in
*podman*)
    # The installer-01-expect sample uses a Dockerfile here-document
    # (COPY <<'EOF'), a Docker/BuildKit feature. Podman/Buildah (through at
    # least 4.9.3 / Buildah 1.33) does not parse COPY heredocs, so this sample
    # only builds under Docker; the Docker job covers it.
    echo "SKIP: non-interactive installer (expect) README sample (COPY heredoc needs Docker/BuildKit; Podman/Buildah lacks it)"
    ;;
*)
# Build a stand-in for an interactive vendor installer. Its prompt strings must
# stay in sync with the expect sample in README.md (installer-01-expect); if they
# drift, the expect script times out and this test fails (which is the point).
mkdir -p "$project/containers/installers"
cat > "$project/containers/installers/hello-installer.run" <<'INSTALLER_EOF'
#!/bin/sh
printf 'Press Enter to view the license '
read _ignore
printf 'END USER LICENSE AGREEMENT (excerpt)\n'
printf 'Do you accept the license? [y/N] '
read answer
case "$answer" in
    y|Y) ;;
    *) echo "License not accepted; aborting." >&2; exit 1 ;;
esac
printf 'Install location: '
read prefix
mkdir -p "$prefix/bin"
cat > "$prefix/bin/hello" <<'HELLO_EOF'
#!/bin/sh
echo "hello, world"
HELLO_EOF
chmod +x "$prefix/bin/hello"
echo "Installation complete."
INSTALLER_EOF
prepare_container_from_sample installer-01-expect readme-installer-expect
output=$(cd "$project" && ./containers/readme-installer-expect/run /opt/hello/bin/hello) || {
    echo "FAIL: non-interactive installer (expect) README sample failed"
    fail=1
    output=""
}
if [ "$output" = "hello, world" ]; then
    echo "PASS: non-interactive installer (expect) README sample drove the installer"
else
    echo "FAIL: non-interactive installer (expect) README sample produced unexpected output: '$output'"
    fail=1
fi
    ;;
esac

echo ""
echo "=== Dockerfile directive samples use the #run-dockerfile: prefix ==="
for sample_id in \
    directive-01-option \
    directive-01b-option-spaces \
    directive-02-mount \
    directive-03-copy-home \
    directive-04-usermount-env \
    directive-05-usermount-multiple \
    directive-06-platform \
    directive-07-http-static \
    directive-08-context-local \
    directive-09-context-remote \
    directive-10-sudo \
    timezone-04-host-env-dockerfile \
    installer-01-expect
do
    assert_sample_uses_prefix "$sample_id"
done
assert_readme_contains "ARG HTTP_INSTALLER"

if [ "$fail" = 0 ]; then
    echo ""
    echo "PASS: README Quick Start examples passed"
fi

exit "$fail"
