#!/bin/sh
# Test: under Podman, images are addressed as localhost/<dir>, so Podman never
# runs short-name resolution (which can prompt for a registry when several
# unqualified-search-registries are configured). Docker keeps the bare name.
#
# The engine is a stub that logs its arguments; a symlink-farm PATH hides any
# real docker/podman, so no daemon is contacted.

set -e

fail=0
WORK=$(mktemp -d)
BIN="$WORK/bin"
LOG="$WORK/engine.log"
mkdir -p "$BIN"

for d in /bin /usr/bin /usr/sbin /sbin; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
        [ -e "$f" ] || continue
        name=$(basename "$f")
        case "$name" in docker|podman) continue ;; esac
        [ -e "$BIN/$name" ] || ln -s "$f" "$BIN/$name" 2>/dev/null || true
    done
done

# Stub engine: log each call. `inspect` returns no hash label (forces a build)
# and a fake image id for the {{.Id}} query the bake step needs.
for e in docker podman; do
    cat > "$BIN/$e" <<STUB
#!/bin/sh
echo "\$*" >> "$LOG"
case "\$1" in
  inspect)
    case "\$*" in
      *'{{.Id}}'*) echo sha256:stub ;;
      *user-command-hash*) ;;
      *) echo 'amd64|' ;;
    esac ;;
esac
exit 0
STUB
    chmod +x "$BIN/$e"
done

printf 'FROM alpine:latest\n' > Dockerfile
name=$(basename "$(pwd)")

# check ENGINE PREFIX
check() {
    : > "$LOG"
    if ! out=$(PATH="$BIN" RUN_DOCKERFILE_USERNS= RUN_DOCKERFILE_ENGINE="$1" ./run true 2>&1); then
        echo "FAIL: $1 — ./run failed: $out"; fail=1; return
    fi
    for want in "build -t $2$name " "run .* $2$name.user-command /bin/run-dockerfile-user-command"; do
        if grep -q -- "^$want" "$LOG"; then
            echo "PASS: $1 uses '$2$name' ($want)"
        else
            echo "FAIL: $1 — no engine call matching '$want'"; sed 's/^/  /' "$LOG"; fail=1
        fi
    done
}

check podman "localhost/"
check docker ""

rm -f Dockerfile
rm -rf "$WORK"
exit $fail
