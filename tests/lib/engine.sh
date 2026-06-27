# Shared test helper: resolve the container engine a test should use for its OWN
# direct image manipulation (seeding fixtures, rmi, inspect), matching the engine
# build-and-run will use - Docker and Podman keep separate image stores, so a test
# that pre-builds a fixture with one engine while ./run uses another would not see
# it. Mirrors build-and-run's resolution: a global rootless override
# (RUN_DOCKERFILE_USERNS) forces bare "podman" (rootless store); else explicit
# RUN_DOCKERFILE_ENGINE wins; else auto-detect with Podman preferred (rootful
# Podman => "sudo podman").
#
# Sets $ENGINE (may be multi-word, e.g. "sudo podman"); use it unquoted so it
# word-splits: `$ENGINE build ...`, `$ENGINE rmi -f ...`, `$ENGINE inspect ...`.
# POSIX sh.
if [ -n "${RUN_DOCKERFILE_USERNS:-}" ]; then
    ENGINE="podman"
elif [ -n "${RUN_DOCKERFILE_ENGINE:-}" ]; then
    ENGINE="$RUN_DOCKERFILE_ENGINE"
elif command -v podman >/dev/null 2>&1; then
    ENGINE="sudo podman"
else
    ENGINE="docker"
fi
