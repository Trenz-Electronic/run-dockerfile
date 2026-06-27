# run-dockerfile

**Tested engines and modes** — each cell runs the full applicable test suite:

|           | Docker | Podman (rootful) | Podman (rootless) |
|-----------|--------|------------------|-------------------|
| **Linux** | [![Linux · Docker](https://github.com/Trenz-Electronic/run-dockerfile/actions/workflows/linux-docker.yml/badge.svg)](https://github.com/Trenz-Electronic/run-dockerfile/actions/workflows/linux-docker.yml) | [![Linux · Podman rootful](https://github.com/Trenz-Electronic/run-dockerfile/actions/workflows/linux-podman-rootful.yml/badge.svg)](https://github.com/Trenz-Electronic/run-dockerfile/actions/workflows/linux-podman-rootful.yml) | [![Linux · Podman rootless](https://github.com/Trenz-Electronic/run-dockerfile/actions/workflows/linux-podman-rootless.yml/badge.svg)](https://github.com/Trenz-Electronic/run-dockerfile/actions/workflows/linux-podman-rootless.yml) |
| **macOS** | [![macOS · Docker](https://github.com/Trenz-Electronic/run-dockerfile/actions/workflows/macos-docker.yml/badge.svg)](https://github.com/Trenz-Electronic/run-dockerfile/actions/workflows/macos-docker.yml) | [![macOS · Podman rootful](https://github.com/Trenz-Electronic/run-dockerfile/actions/workflows/macos-podman-rootful.yml/badge.svg)](https://github.com/Trenz-Electronic/run-dockerfile/actions/workflows/macos-podman-rootful.yml) | [![macOS · Podman rootless](https://github.com/Trenz-Electronic/run-dockerfile/actions/workflows/macos-podman-rootless.yml/badge.svg)](https://github.com/Trenz-Electronic/run-dockerfile/actions/workflows/macos-podman-rootless.yml) |

A single bash script that turns Dockerfiles into ready-to-run applications without long and error-prone container command lines by automating user mapping, volume mounts, image rebuilds, and more. It enables simultaneous execution of multiple tools with conflicting OS or library dependencies in your workflow by simply prefixing tool invocations with a symlink to the build-and-run script.

run-dockerfile handles the common setup work for containerized development:
- **User/group mapping** - No more permission headaches with mounted volumes
- **Volume mounting** - Your project files are automatically available
- **Image management** - Containers are built and rebuilt automatically as needed
- **TTY handling** - Interactive sessions just work
- **Common options** - Keep repeated container engine options in the Dockerfile
- **Cross-architecture builds** - Run builds in a target-architecture container when your container engine supports that platform
- **Large tool installation files outside build context** - Easily incorporated into your Dockerfile, just invoke the installer. Many installers offer a command-line flag for a quiet, unattended install; when none is available, a small `expect` script can drive the prompts (see [Non-interactive installers](#non-interactive-installers)).

## Quick start

Follow these steps:

1. **Create a container directory** with your desired name and Dockerfile
   <!-- readme-sample: quickstart-01-create-container -->
   ```bash
   mkdir -p containers/my-container
   cat > containers/my-container/Dockerfile <<'EOF'
   FROM buildpack-deps:bookworm
   EOF
   cat > Makefile <<'EOF'
   all:
   	@echo "README example build"
   EOF
   ```
   The root `Makefile` is just a stand-in build target so the `make` command in step 4 has something to run — replace it with your real project.

2. **Add run-dockerfile** as a submodule to your project (if your project is not a git repository yet, run `git init` first):
   <!-- readme-sample: quickstart-02-add-run-dockerfile -->
   ```bash
   git submodule add https://github.com/Trenz-Electronic/run-dockerfile.git run-dockerfile
   ```
   Or add it by any other compatible method.

3. **Create a symlink** to the build-and-run script:
   <!-- readme-sample: quickstart-03-create-run-symlink -->
   ```bash
   (cd containers/my-container && ln -s ../../run-dockerfile/build-and-run run)
   ```
   This is the crucial step. The `run` symlink must live next to the Dockerfile; run-dockerfile uses that directory as the Docker context.

4. **Run commands** inside the container without long Docker command lines:
   <!-- readme-sample: quickstart-04-run-commands -->
   ```bash
   # verify that the local directory is mapped by listing the files
   ./containers/my-container/run ls -l .
   # verify my user inside the container
   ./containers/my-container/run whoami
   # verify the CPU architecture the container is running on:
   ./containers/my-container/run uname -m
   # run your project build command using the CPU count visible inside the container
   ./containers/my-container/run sh -lc 'make -j$(nproc)'
   ```

The image is built automatically on the first run and rebuilt when the Dockerfile's build context changes.

**Important:** Create your container directories in your project (not inside the `run-dockerfile/` submodule) so they can be version-controlled with your code.

## Docker options on the command line

Pass Docker run options directly on the command line:

<!-- readme-sample: options-01-command-line -->
```bash
./containers/my-container/run -e CC=clang sh -lc 'test "$CC" = clang'  # Environment variables
./containers/my-container/run -v "$PWD:/project:ro" test -d /project   # Volume mounts
./containers/my-container/run -p 80 true                               # Port mapping
./containers/my-container/run --network host true                      # Network mode
./containers/my-container/run --cpus 1 --memory 512m true              # Resource limits
```

**Forwarding environment variables:** `-e`/`--env` accepts two forms. `-e NAME=value` sets the variable to a literal value inside the container; `-e NAME` (no `=value`) forwards `NAME`'s *current value from your host environment* — handy for values you would rather not hard-code, such as `-e DISPLAY` for X11. Either way, run-dockerfile also re-exports the variable across the container's internal `su` privilege drop, so it stays set for your command. The same two forms work in the Dockerfile via [`#run-dockerfile: option`](#docker-options-in-the-dockerfile) (`#run-dockerfile: option -e NAME=value` and `#run-dockerfile: option -e NAME`).

**Supported command-line options:**
- `-e`/`--env` - Environment variables
- `-v`/`--volume` - Volume mounts
- `-p`/`--publish` - Port mapping
- `-w`/`--workdir` - Working directory
- `--network`/`--net` - Network mode
- `--device` - Device access
- `--cpus` - CPU limit
- `-m`/`--memory` - Memory limit
- `--gpus` - GPU access
- `--name` - Container name
- `--privileged`, `--read-only` - Supported boolean flags
- `-h`/`--help` - Show usage

**Important:** only the above listed options are supported on the command line. Anything else — including an unrecognized `--flag` — is treated as the start of the command to run inside the container, not as a `docker run` option. To pass an option run-dockerfile does not recognize, put it in the Dockerfile with `#run-dockerfile: option` instead.

**Environment variables:**
- `RUN_DOCKERFILE_VERBOSE=1` - Show informational messages (mount directives, file collection, etc.); only the literal value `1` enables verbose output.

## Dockerfile directives

run-dockerfile extends Dockerfiles with special comment directives.

Directives use a `#run-dockerfile:` prefix followed by the directive keyword and its value, for example `#run-dockerfile: option --network host`. The `#` must start the line, and prefixed directives may appear **anywhere** in the Dockerfile — by convention, keep them grouped at the top (or bottom) so they are easy to find.

The older unprefixed forms (`#option:`, `# platform:`, …) still work but are **deprecated**: they are honored only in the first 20 lines and print a deprecation warning pointing at the prefixed replacement. The examples below use the prefixed form.

### Docker options in the Dockerfile

For any options you want to always be present on the command line, but don't bother to type them in every time, use the `#run-dockerfile: option` pragma in your Dockerfile:

<!-- readme-sample: directive-01-option -->
```dockerfile
#run-dockerfile: option --security-opt seccomp=unconfined
#run-dockerfile: option --cap-add SYS_PTRACE
#run-dockerfile: option --network host
FROM ubuntu:22.04
```

Each `#run-dockerfile: option` line represents one Docker run option. If the option has a value,
write the option name first and the value after the first space; the whole
remaining value is passed literally, so spaces and glob characters are
preserved:

<!-- readme-sample: directive-01b-option-spaces -->
```dockerfile
#run-dockerfile: option -v /tmp/my cache:/cache
#run-dockerfile: option -e TOOL_FLAGS=--mode fast
#run-dockerfile: option --mount type=bind,source=/tmp/my cache,target=/cache-ro,readonly
FROM ubuntu:22.04
```

Use multiple `#run-dockerfile: option` lines for multiple Docker run options.

To pass an environment variable, `#run-dockerfile: option -e NAME=value` sets a literal value and `#run-dockerfile: option -e NAME` (no value) forwards `NAME` from your host environment — both are preserved across the container's internal `su` (see [Forwarding environment variables](#docker-options-on-the-command-line) above).

### Fine-tune volume mapping

The default behavior of run-dockerfile is to search for the root of the git repository and volume mount it; failing that, it will volume mount the current directory. The default behavior corresponds to `#run-dockerfile: mount .git pwd`.

The `#run-dockerfile: mount` directive accepts whitespace-separated keywords:
- `.git` - Root of the git repository (searches upward from current directory)
- `pwd` - Current working directory
- `home` - Home directory — do not use with untrusted containers

The keywords are tried in order and the first available directory is mounted; if none are available, run-dockerfile exits with an error.

**Example**: Restrict container to git repository only, to avoid any security lapses:
<!-- readme-sample: directive-02-mount -->
```dockerfile
#run-dockerfile: mount .git
FROM ubuntu:22.04
# Only git repo is mounted, not entire $HOME
```

Multiple `#run-dockerfile: mount` directives are also supported. They are accumulated in file order.

### Select the files to be in your home directory

To have files copied over to your home directory in the container, use the `#run-dockerfile: copy.home` directive. It takes just a single path to a file relative to your home directory. For multiple files, simply use the directive multiple times.

In this example, there are two license files copied over using `#run-dockerfile: copy.home`
<!-- readme-sample: directive-03-copy-home -->
```dockerfile
#run-dockerfile: copy.home .license.dat
#run-dockerfile: copy.home .config/my-tool/license.json
FROM ubuntu:22.04
```

The files are collected at **run time**, not build time — the image itself never contains them. On every `./run` invocation, build-and-run tars the listed files on the host (just before `docker run`), bind-mounts the tarball into the container, and the entry script extracts it into the in-container user's `$HOME`. This means:

- The host files do **not** need to exist when the image is being built.
- Each `./run` invocation **does** require all listed files; if any is missing, `build-and-run` exits with an error before the container starts.
- Changes made to these files inside the container are not propagated back to the host.

### Mount specific directories

Use the `#run-dockerfile: usermount` directive to mount specific directories into the container. Unlike `#run-dockerfile: mount`, this directive creates the directory if it doesn't exist (as the current user, not root). Each directory is mounted at the **same path inside the container** as on the host, so `$HOME/.cache/pip` on the host appears at `$HOME/.cache/pip` in the container.

Environment variables are expanded, so you can use $HOME, $PWD, etc.:

<!-- readme-sample: directive-04-usermount-env -->
```dockerfile
#run-dockerfile: usermount $HOME/projects/shared-cache
#run-dockerfile: usermount $HOME/.local/share/myapp
FROM ubuntu:22.04
```

Each `#run-dockerfile: usermount` line is a single path (which may contain spaces); use multiple lines for multiple paths:

<!-- readme-sample: directive-05-usermount-multiple -->
```dockerfile
#run-dockerfile: usermount $HOME/.cache/pip
#run-dockerfile: usermount $HOME/.cache/npm
FROM ubuntu:22.04
```

This is useful when you need persistent storage for specific directories without exposing your entire home directory.

### Platform selection

Specify the target platform:

<!-- readme-sample: directive-06-platform -->
```dockerfile
#run-dockerfile: platform arm64
FROM ubuntu:22.04
```

Supported values: Any Docker platform string (e.g., `arm64`, `amd64`, `linux/arm/v7`, `linux/arm64`)

This feature is useful when you want to build inside an emulated target-architecture environment instead of setting up a cross-compiler toolchain. run-dockerfile passes the platform to Docker; for foreign architectures, Docker must already be configured with the required binfmt/QEMU support. Builds under emulation can be significantly slower.

### HTTP static file serving

Serve local directories via HTTP during image builds (useful for large installers):

<!-- readme-sample: directive-07-http-static -->
```dockerfile
#run-dockerfile: http.static INSTALLER=../installers
FROM buildpack-deps:bookworm

ARG HTTP_INSTALLER
RUN wget ${HTTP_INSTALLER}/large-sdk-installer.run && sh ./large-sdk-installer.run && rm ./large-sdk-installer.run
```

**Note:** Relative paths are resolved from the Dockerfile's directory. The directory must exist before build. Declare `ARG HTTP_<KEY>` after `FROM`, before any `RUN` that uses the generated URL; for `#run-dockerfile: http.static INSTALLER=...`, declare `ARG HTTP_INSTALLER`.

The script automatically:
- Starts a temporary HTTP server on a random port
- Passes the URL as `HTTP_<KEY>` build argument
- Cleans up the server after build completes

**Caveat:** Changes to files in directories served by `#run-dockerfile: http.static` do not trigger automatic rebuilds. Use `docker rmi <image-name>` to force a rebuild (the image is tagged with the container directory name — see [Project structure](#project-structure)).

### BuildKit named contexts

Pass Docker BuildKit named contexts with `#run-dockerfile: context`:

<!-- readme-sample: directive-08-context-local -->
```dockerfile
#run-dockerfile: context installer=../installers
FROM ubuntu:22.04

COPY --from=installer large-sdk-installer.run /tmp/large-sdk-installer.run
RUN sh /tmp/large-sdk-installer.run && rm /tmp/large-sdk-installer.run
```

Multiple directives are allowed. The context name must match `[a-z_][a-z0-9_.-]*`; context names are lowercase because Docker/BuildKit resolves `COPY --from=<name>` through image-reference-style rules on current Docker versions, and uppercase names can fail before the build with an invalid reference error. The value is passed to `docker build --build-context name=value` without shell evaluation. Local relative paths are resolved from the Dockerfile's directory and must exist before build. Remote, Git, image, and `target:` context values are passed through unchanged, for example:

<!-- readme-sample: directive-09-context-remote -->
```dockerfile
#run-dockerfile: context base=docker-image://alpine:latest
#run-dockerfile: context src=https://github.com/org/repo.git
```

**Caveat:** Changes to files inside named contexts do not trigger automatic rebuilds. Changing the `#run-dockerfile: context` line itself does trigger a rebuild. Use `docker rmi <image-name>` to force a rebuild after changing only named-context contents.

### Sudo configuration

If you need `sudo` access inside the container, use the `#run-dockerfile: sudo` directive and make sure sudo has been installed, as in the following example:

<!-- readme-sample: directive-10-sudo -->
```dockerfile
#run-dockerfile: sudo all
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y sudo
```

With `#run-dockerfile: sudo all`, run-dockerfile creates a sudoers entry allowing passwordless sudo for the container user. Without this directive, even if sudo is installed, it won't be configured for the container user.

### GUI applications (X11)

run-dockerfile can run X11 applications with minimal configuration:

```dockerfile
# X11 Application Container
#run-dockerfile: copy.home .Xauthority
#run-dockerfile: option -e DISPLAY
#run-dockerfile: option -v /tmp/.X11-unix:/tmp/.X11-unix
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    x11-apps \
    freecad \
    kicad \
    && rm -rf /var/lib/apt/lists/*
```

Usage:
```bash
# Test with simple X11 app
./containers/x11-apps/run xclock

# Run FreeCAD for mechanical design
./containers/x11-apps/run freecad

# Run KiCad for PCB design
./containers/x11-apps/run kicad
```

**Why `#run-dockerfile: copy.home .Xauthority`?** This securely copies only the X11 authentication file instead of mounting your entire home directory, following the principle of least privilege.

On Linux, X11 typically also requires forwarding `DISPLAY` and mounting `/tmp/.X11-unix` as shown above. Some setups instead require `--network host`, a remote X server, or Docker Desktop-specific display configuration.

### Timezone and locale

Timezone and locale settings are useful for GUI applications that should match the desktop environment, and for tools that produce timestamps or other locale-dependent output in regional settings.

For reproducible project containers, set the timezone and locale in the Dockerfile:

<!-- readme-sample: timezone-01-alpine-fixed -->
```dockerfile
FROM alpine:latest
RUN apk add --no-cache tzdata
ENV TZ=Etc/UTC
```

<!-- readme-sample: timezone-02-debian-fixed -->
```dockerfile
FROM ubuntu:22.04
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends tzdata \
    && rm -rf /var/lib/apt/lists/*
ENV TZ=Etc/UTC
ENV LANG=C.UTF-8
```

For a generated regional locale, install `locales` and enable the locale explicitly:

<!-- readme-sample: timezone-03-debian-regional-locale -->
```dockerfile
FROM ubuntu:22.04
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends locales \
    && sed -i 's/^# *de_DE.UTF-8 UTF-8/de_DE.UTF-8 UTF-8/' /etc/locale.gen \
    && locale-gen \
    && rm -rf /var/lib/apt/lists/*
ENV LANG=de_DE.UTF-8
ENV LC_ALL=de_DE.UTF-8
```

If you want a project container to use host-provided values, forward them from the Dockerfile with `#run-dockerfile: option`:

<!-- readme-sample: timezone-04-host-env-dockerfile -->
```dockerfile
#run-dockerfile: option -e TZ
#run-dockerfile: option -e LANG
FROM buildpack-deps:bookworm
```

The same settings can be provided for one command on the command line:

<!-- readme-sample: timezone-05-command-fixed -->
```bash
./containers/my-container/run -e TZ=Etc/UTC date +%z
./containers/my-container/run -e LANG=C.UTF-8 sh -lc 'printf "%s\n" "$LANG"'
```

<!-- readme-sample: timezone-06-command-host-env -->
```bash
TZ=Etc/UTC LANG=C.UTF-8 ./containers/my-container/run -e TZ -e LANG sh -lc 'printf "%s %s\n" "$TZ" "$LANG"'
```

On hosts that provide `/etc/localtime`, you can also use the host timezone file directly:

<!-- readme-sample: timezone-07-command-localtime -->
```bash
./containers/my-container/run -v /etc/localtime:/etc/localtime:ro date +%z
```

`/etc/localtime` works on common Linux hosts and Docker Desktop/macOS setups. `/etc/timezone` is Debian-like/Linux-specific and is often absent on macOS. `TZ=Region/City` needs timezone data in the image; in minimal images, install `tzdata` or mount `/etc/localtime`.

## Non-interactive installers

Vendor tool installers are often interactive: they page through a license and wait for you to type `yes`. A
`docker build` has no terminal attached, so such an installer stalls or aborts.
run-dockerfile only delivers the installer into the build (see
[HTTP static file serving](#http-static-file-serving) and
[BuildKit named contexts](#buildkit-named-contexts)); running it unattended is
ordinary Dockerfile work.

Prefer the installer's own unattended flag whenever it has one (for example
`--mode unattended`, `--accept-license`, or `-a`). When the installer instead
pages a license (waiting for a keypress) or asks conditional questions that a
fixed set of answers cannot satisfy, drive it with `expect`. Because
run-dockerfile always enables BuildKit, the `expect` script can be written
inline with a `COPY` heredoc instead of shipping a separate file:

<!-- readme-sample: installer-01-expect -->
```dockerfile
#run-dockerfile: http.static INSTALLER=../installers
FROM buildpack-deps:bookworm
RUN apt-get update && apt-get install -y --no-install-recommends expect \
    && rm -rf /var/lib/apt/lists/*

ARG HTTP_INSTALLER
RUN wget -q ${HTTP_INSTALLER}/hello-installer.run

COPY <<'EOF' /tmp/drive-installer.exp
# Wait up to 5 minutes per prompt; use -1 for installers that can run longer.
set timeout 300
spawn sh ./hello-installer.run
expect "Press Enter to view the license"
send "\r"
expect "Do you accept the license?"
send "y\r"
expect "Install location:"
send "/opt/hello\r"
expect "Installation complete."
expect eof
EOF
RUN expect /tmp/drive-installer.exp
RUN /opt/hello/bin/hello
```

Match each `expect` line to a prompt the installer actually prints and each
`send` to the answer it wants. These scripts are brittle by nature, so rebuild
(and re-test) whenever the installer version changes. The example drives a
stand-in `hello-installer.run` that prints a license, asks for confirmation and
an install path, then installs a small `hello` command; swap in your real
installer and its prompts.

> **Engine note:** the `COPY <<'EOF'` here-document above needs a builder that
> parses Dockerfile here-documents. Docker/BuildKit always does, and **Buildah has
> supported `RUN`/`COPY`/`ADD` here-documents since v1.33.0** (Nov 2023, bundled with
> Podman ≈ 4.8+), so this sample builds under current Podman too. The one catch is
> distro packaging: some Buildah packages were shipped with here-document support
> *patched out* to avoid a BuildKit dependency — notably Debian/Ubuntu, including the
> Buildah behind `apt install podman` on Ubuntu 24.04 LTS (1.33.5); Debian restored
> it in `buildah 1.35.3+ds1-2` (July 2024). If your Podman/Buildah build is one of
> those (it fails with `copier: stat "/<<EOF": no such file or directory`), either
> use a Buildah that retains here-document support, or put the `expect` script in a
> file next to the Dockerfile and `COPY drive-installer.exp /tmp/` instead of the
> inline here-document.

## Project structure

run-dockerfile is flexible about where you place your container directories. The example structure, which is in no way enforced, is:

```
my-project/
├── run-dockerfile/          # git submodule
│   ├── build-and-run
│   └── ...
├── containers/              # your container definitions
│   ├── build-env/
│   │   ├── Dockerfile
│   │   └── run -> ../../run-dockerfile/build-and-run
│   └── test-env/
│       ├── Dockerfile
│       └── run -> ../../run-dockerfile/build-and-run
└── src/
    └── ...
```

As long as each container directory's `run` symlink points to `run-dockerfile/build-and-run`, it works.

**Image naming:** Each container directory name becomes the Docker image tag — `containers/build-env/` builds an image named `build-env`. It must therefore be a valid lowercase Docker image name matching `[a-z0-9][a-z0-9._-]*` (use `build-env`, not `Build_Env`); run-dockerfile checks this up front and exits with a clear message if the name is invalid. This is also the name to pass to `docker rmi <image-name>` when forcing a rebuild.

## Container engine: Podman or Docker

run-dockerfile works with **Podman** or **Docker**. You normally don't configure anything — it picks an engine automatically:

- If only one of `docker` / `podman` is installed, it uses that one.
- If **both** are installed, it prefers **Podman**.
- If neither is installed, it stops with a clear error.

Override the choice with the `RUN_DOCKERFILE_ENGINE` environment variable (taken verbatim, so you can include `sudo`):

```sh
RUN_DOCKERFILE_ENGINE=docker ./run make          # force Docker
RUN_DOCKERFILE_ENGINE="sudo podman" ./run make   # force rootful Podman
RUN_DOCKERFILE_USERNS=keep-id ./run make         # force rootless Podman (no sudo)
```

`RUN_DOCKERFILE_USERNS=<mode>` forces rootless Podman with `--userns=<mode>` for *every* container, without adding the `#run-dockerfile: rootless` directive (below) to each Dockerfile — handy for running a whole project rootless. A per-Dockerfile directive still takes precedence.

To see which engine will be used here, without building or running anything:

```sh
RUN_DOCKERFILE_PRINT_ENGINE=1 ./run
```

**Rootful Podman** has no background daemon or `docker`-style group, so it needs `sudo`; run-dockerfile invokes it as `sudo podman` while the script itself keeps running as you, so your files stay owned by you. When both engines are present and you want Docker, set `RUN_DOCKERFILE_ENGINE=docker`.

**Rootless Podman** is opt-in per project, because rootless containers remap user IDs through your `subuid` range — a non-root tool would otherwise write bind-mounted files owned by an unusable shifted UID. Add this directive to the Dockerfile to run rootless and pin your host UID 1:1 so file ownership stays correct:

```Dockerfile
#run-dockerfile: rootless --userns=keep-id
FROM debian:12
```

`keep-id` is the supported mode: it maps your host UID 1:1 into the container so bind-mounted files stay owned by you. The value is passed verbatim to `podman run --userns=...`, so other Podman user-namespace modes are accepted too — but only `keep-id` preserves host ownership; see Podman's [`podman run --userns`](https://docs.podman.io/en/latest/markdown/podman-run.1.html#userns-mode) documentation for what the other values do.

**Only rootless Podman is supported for now.** This directive forces the rootless (non-`sudo`) Podman engine and requires `podman`. Rootless *Docker* is not supported: `--userns=keep-id` does not exist there, which is the first hurdle among several.

**Podman and short image names:** unlike Docker, Podman does not assume Docker Hub for unqualified image names. If a `FROM` line uses a short name that Podman cannot resolve (e.g. `FROM buildpack-deps:bookworm` fails while `FROM alpine` works via Podman's built-in aliases), either add `docker.io` to your Podman config:

```sh
# system-wide (rootful Podman):
echo 'unqualified-search-registries = ["docker.io"]' | sudo tee /etc/containers/registries.conf.d/99-docker-io.conf
```

or fully qualify the image (`FROM docker.io/library/buildpack-deps:bookworm`), which works with both engines.

## Requirements

**On the host:**

- Linux or macOS with bash and a container engine — **Podman or Docker** (see [Container engine](#container-engine-podman-or-docker)).
- For foreign-architecture `#run-dockerfile: platform` builds/runs, the engine must have binfmt/QEMU support configured for the requested platform.
- GNU `tar` is optional; when unavailable, run-dockerfile uses a portable metadata-manifest hash for rebuild detection.
- `python3` — only when using `#run-dockerfile: http.static`.
- Linux `ip` command from iproute2 — only when using `#run-dockerfile: http.static` on Linux.

**In the image:**

- `/bin/sh`, `su`, and writable `/etc/passwd` and `/etc/group` — users and groups are created by appending entries directly, so no `useradd` is needed. Standard Debian, Ubuntu, Fedora and Alpine base images all qualify; scratch and distroless images do not.
- `tar` with gzip support — only when using `#run-dockerfile: copy.home` (the files are delivered as a tarball extracted inside the container).
- `sudo` — only when using `#run-dockerfile: sudo all`; run-dockerfile creates `/etc/sudoers.d/` if it is missing.

## Technical details

- Creates a temporary user inside the container matching your host UID/GID; conflicting image user/group names get deterministic fallback names such as `${name}_${id}` and `${name}_${id}_a`
- Uses `su` for privilege de-escalation (no sudo requirement)
- Optionally configures sudoers with `#run-dockerfile: sudo all` directive
- Preserves your working directory inside the container
- Auto-detects TTY for interactive sessions
- Always uses Docker BuildKit (the modern build path, the engine default since Docker 23.0); `RUN --mount`, cache mounts, build secrets, and named contexts work out of the box
- Automatically rebuilds the image when detecting changes in the Dockerfile's build context directory using the hash stored as a label in the Docker image. Mounted files outside that context do not trigger rebuilds by themselves.

## Security considerations

run-dockerfile has **secure defaults for trusted Dockerfiles**:

- ✅ No $HOME exposure - SSH keys, GPG keys, AWS credentials stay protected
- ✅ Git-aware - automatically mounts only your repository root
- ✅ Minimal access - falls back to current directory if not in git repo

**When you need $HOME access** (e.g., for shell configurations, SSH keys):

```dockerfile
#run-dockerfile: mount home
FROM ubuntu:22.04
```

**When you need specific files only** (most secure):

```dockerfile
#run-dockerfile: copy.home .license.dat
#run-dockerfile: copy.home .ssh/config
FROM ubuntu:22.04
```

The default behavior helps avoid accidental host exposure in CI/CD pipelines: nothing outside the project directory is exposed to the container unless a trusted Dockerfile or command line explicitly asks for it.

When using `#run-dockerfile: http.static`, run-dockerfile briefly starts a temporary HTTP server on a random host port during the image build and serves files only under a high-entropy temporary URL prefix passed through `HTTP_<KEY>`. Treat that URL as visible to other users who can inspect build arguments or process output while the build is running; serve only trusted, non-secret files.

**Trust model:** run-dockerfile is intended for Dockerfiles you trust — your own projects and submodules you have reviewed. Directive values are never evaluated by a shell on the host, but the directives themselves are powerful: `#run-dockerfile: option` can pass arbitrary `docker run` flags such as `--privileged` or `-v /:/host`, `#run-dockerfile: usermount` creates directories on the host, and `#run-dockerfile: copy.home` copies files out of your host `$HOME`. Review the Dockerfile before running `./run` on a project you did not write.

## Testing

The test suite lives in `tests/`, one directory per case. Run it with `tests/run`:

- `tests/run --all` — run the whole suite.
- `tests/run 0017` — run a single test. The argument matches a test **directory by name prefix** (so `0017` selects `0017_auto_rebuild`), and must match exactly one directory.
- `tests/run 0001 0003` — run several, each given as a prefix.
- `tests/run --no-cleanup --all` — run everything but keep the test containers/images afterwards for debugging.
- `tests/run --cleanup` — remove leftover test containers/images without running any test.

### What runs in which CI cell

The six status badges at the top of this README are CI **cells** — {Linux, macOS} × {Docker, Podman rootful, Podman rootless} — each running `tests/run --all`. A handful of tests need a capability a given cell can't provide, so they are skipped there (always reported, never silent). Each test declares what it needs with a `# caps:` line, and each cell declares what it provides.

Capability → the test(s) it gates:

- `qemu-arm64` → 0002, `qemu-amd64` → 0003, `qemu-armv7` → 0004 — running a foreign-architecture `#run-dockerfile: platform` image
- `cgroups` → 0011, 0014 — container resource limits are observable
- `python3` → 0008, 0029, 0030 — host HTTP server for `#run-dockerfile: http.static`
- `linux` → 0010 — host-side Linux behavior (e.g. `/dev/pts`)
- `rootless-podman` → 0046 — bare rootless Podman with `--userns=keep-id`
- `home-bind` → 0006 — a bind-mounted private (mode-700) `$HOME` is readable by the in-container user

Each cell skips the tests whose capability it does not provide:

- **Linux · Docker** and **Linux · Podman (rootful)** → 0046
- **Linux · Podman (rootless)** → 0002, 0003, 0004
- **macOS · Docker** → 0010, 0011, 0014, 0046
- **macOS · Podman (rootful)** → 0003, 0004, 0008, 0010, 0011, 0014, 0029, 0030, 0046
- **macOS · Podman (rootless)** → the same as rootful, **plus** 0006

These lists are derived from each test's `# caps:` line and each cell's `cell-caps` (in `.github/workflows/*.yml`); see the "Capability tags and the engine/OS support matrix" section of `CLAUDE.md` for the mechanism and maintainer notes.

## License

MIT License - See [LICENSE](LICENSE) for details.
