# docker-booster

[![Test Suite](https://github.com/Trenz-Electronic/docker-booster/actions/workflows/test.yml/badge.svg)](https://github.com/Trenz-Electronic/docker-booster/actions/workflows/test.yml)
[![macOS Test Suite](https://github.com/Trenz-Electronic/docker-booster/actions/workflows/test-macos.yml/badge.svg)](https://github.com/Trenz-Electronic/docker-booster/actions/workflows/test-macos.yml)

A single bash script that turns Dockerfiles into ready-to-run applications without long and error-prone docker command lines by automating user mapping, volume mounts, image rebuilds, and more. When your workflow requires multiple tools with conflicting OS or library dependencies, this is exactly where docker-booster shines.

docker-booster handles the common setup work for containerized development:
- **User/group mapping** - No more permission headaches with mounted volumes
- **Volume mounting** - Your project files are automatically available
- **Image management** - Containers are built and rebuilt automatically as needed
- **TTY handling** - Interactive sessions just work
- **Common options** - Keep repeated Docker options in the Dockerfile
- **Cross-architecture builds** - Run builds in a target-architecture container when Docker supports that platform
- **Large source files outside build context** - Easily incorporated into your Dockerfile

## Quick Start

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

2. **Add docker-booster** as a submodule to your project (if your project is not a git repository yet, run `git init` first):
   <!-- readme-sample: quickstart-02-add-docker-booster -->
   ```bash
   git submodule add https://github.com/Trenz-Electronic/docker-booster.git docker-booster
   ```
   Or clone it directly:
   ```bash
   git clone https://github.com/Trenz-Electronic/docker-booster.git
   ```

3. **Create a symlink** to the build-and-run script:
   <!-- readme-sample: quickstart-03-create-run-symlink -->
   ```bash
   (cd containers/my-container && ln -s ../../docker-booster/build-and-run run)
   ```
   This is the crucial step. The `run` symlink must live next to the Dockerfile; docker-booster uses that directory as the Docker context.

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

**Important:** Create your container directories in your project (not inside the `docker-booster/` submodule) so they can be version-controlled with your code.

## Docker options on the command line

Pass docker run options directly on the command line:

<!-- readme-sample: options-01-command-line -->
```bash
./containers/my-container/run -e CC=clang sh -lc 'test "$CC" = clang'  # Environment variables
./containers/my-container/run -v "$PWD:/project:ro" test -d /project   # Volume mounts
./containers/my-container/run -p 80 true                               # Port mapping
./containers/my-container/run --network host true                      # Network mode
./containers/my-container/run --cpus 1 --memory 512m true              # Resource limits
```

**Forwarding environment variables:** `-e`/`--env` accepts two forms. `-e NAME=value` sets the variable to a literal value inside the container; `-e NAME` (no `=value`) forwards `NAME`'s *current value from your host environment* — handy for values you would rather not hard-code, such as `-e DISPLAY` for X11. Either way, docker-booster also re-exports the variable across the container's internal `su` privilege drop, so it stays set for your command. The same two forms work in the Dockerfile via [`#option:`](#docker-options-in-the-dockerfile) (`#option: -e NAME=value` and `#option: -e NAME`).

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

Important: only the above listed options are supported on the command line. Anything else — including an unrecognized `--flag` — is treated as the start of the command to run inside the container, not as a `docker run` option. To pass an option docker-booster does not recognize, put it in the Dockerfile with `#option:` instead.

**Environment variables:**
- `DOCKER_BOOSTER_VERBOSE=1` - Show informational messages (mount directives, file collection, etc.); only the literal value `1` enables verbose output.

## Dockerfile Directives

docker-booster extends Dockerfiles with special comment directives.

All docker-booster directives must appear in the first 20 lines of the Dockerfile. Both `#directive:` and `# directive:` forms are accepted; examples below use the project's conventional spelling for each directive.

### Docker options in the Dockerfile

For any options you want to always be present on the command line, but don't bother to type them in every time, use the `#option:` pragma in your Dockerfile:

<!-- readme-sample: directive-01-option -->
```dockerfile
#option: --security-opt seccomp=unconfined
#option: --cap-add SYS_PTRACE
#option: --network host
FROM ubuntu:22.04
```

Each `#option:` line represents one Docker option. If the option has a value,
write the option name first and the value after the first space; the whole
remaining value is passed literally, so spaces and glob characters are
preserved:

```dockerfile
#option: -v /tmp/my cache:/cache
#option: -e TOOL_FLAGS=--mode fast
#option: --mount type=bind,source=/tmp/my cache,target=/cache,readonly
FROM ubuntu:22.04
```

Use multiple `#option:` lines for multiple Docker options.

To pass an environment variable, `#option: -e NAME=value` sets a literal value and `#option: -e NAME` (no value) forwards `NAME` from your host environment — both are preserved across the container's internal `su` (see [Forwarding environment variables](#docker-options-on-the-command-line) above).

### Fine-tune volume mapping

The default behaviour of docker-booster is to search for the root of the git repository and volume mount it; failing that, it will volume mount the current directory. The default behaviour corresponds to `#mount: .git pwd`.

The `#mount:` directive accepts whitespace-separated keywords:
- `.git` - Root of the git repository (searches upward from current directory)
- `pwd` - Current working directory
- `home` - Home directory, do not use with untrusted containers

The keywords are tried in order and the first available directory is mounted; if none are available, docker-booster exits with an error.

**Example**: Restrict container to git repository only, to avoid any security lapses:
<!-- readme-sample: directive-02-mount -->
```dockerfile
#mount: .git
FROM ubuntu:22.04
# Only git repo is mounted, not entire $HOME
```

Multiple `#mount:` directives are also supported. They are accumulated in file order.

### Select the files to be in your home directory

To have files copied over to your home directory in the container, use the `#copy.home:` directive. It takes just a single path to a file relative to your home directory. For multiple files, simply use the directive multiple times.

In this example, there are two license files copied over using #copy.home:
<!-- readme-sample: directive-03-copy-home -->
```dockerfile
#copy.home: .license.dat
#copy.home: .config/my-tool/license.json
FROM ubuntu:22.04
```

The files are collected at **run time**, not build time — the image itself never contains them. On every `./run` invocation, build-and-run tars the listed files on the host (just before `docker run`), bind-mounts the tarball into the container, and the entry script extracts it into the in-container user's `$HOME`. This means:

- The host files do **not** need to exist when the image is being built.
- Each `./run` invocation **does** require all listed files; if any is missing, `build-and-run` exits with an error before the container starts.
- Changes made to these files inside the container are not propagated back to the host.

### Mount specific directories

Use the `#usermount:` directive to mount specific directories into the container. Unlike `#mount:`, this directive creates the directory if it doesn't exist (as the current user, not root). Each directory is mounted at the **same path inside the container** as on the host, so `$HOME/.cache/pip` on the host appears at `$HOME/.cache/pip` in the container.

Environment variables are expanded, so you can use $HOME, $PWD, etc.:

<!-- readme-sample: directive-04-usermount-env -->
```dockerfile
#usermount: $HOME/projects/shared-cache
#usermount: $HOME/.local/share/myapp
FROM ubuntu:22.04
```

Each `#usermount:` line is a single path (which may contain spaces); use multiple lines for multiple paths:

<!-- readme-sample: directive-05-usermount-multiple -->
```dockerfile
#usermount: $HOME/.cache/pip
#usermount: $HOME/.cache/npm
FROM ubuntu:22.04
```

This is useful when you need persistent storage for specific directories without exposing your entire home directory.

### Platform Selection

Specify the target platform in the first 20 lines:

<!-- readme-sample: directive-06-platform -->
```dockerfile
# platform: arm64
FROM ubuntu:22.04
```

Supported values: Any Docker platform string (e.g., `arm64`, `amd64`, `linux/arm/v7`, `linux/arm64`)

This feature is useful when you want to build inside an emulated target-architecture environment instead of setting up a cross-compiler toolchain. docker-booster passes the platform to Docker; for foreign architectures, Docker must already be configured with the required binfmt/QEMU support. Builds under emulation can be significantly slower.

### HTTP Static File Serving

Serve local directories via HTTP during image builds (useful for large installers):

<!-- readme-sample: directive-07-http-static -->
```dockerfile
#http.static: INSTALLER=../installers
FROM buildpack-deps:bookworm

ARG HTTP_INSTALLER
RUN wget ${HTTP_INSTALLER}/large-sdk-installer.run && sh ./large-sdk-installer.run && rm ./large-sdk-installer.run
```

**Note:** Relative paths are resolved from the Dockerfile's directory. The directory must exist before build. Declare `ARG HTTP_<KEY>` after `FROM` before using the generated URL; for `#http.static: INSTALLER=...`, declare `ARG HTTP_INSTALLER`.

The script automatically:
- Starts a temporary HTTP server on a random port
- Passes the URL as `HTTP_<KEY>` build argument
- Cleans up the server after build completes

**Caveat:** Changes to files in directories served by `#http.static:` do not trigger automatic rebuilds. Use `docker rmi <image-name>` to force a rebuild (the image is tagged with the container directory name — see [Project Structure](#project-structure)).

### BuildKit Named Contexts

Pass Docker BuildKit named contexts with `#context:`:

<!-- readme-sample: directive-08-context-local -->
```dockerfile
#context: installer=../installers
FROM ubuntu:22.04

COPY --from=installer large-sdk-installer.run /tmp/large-sdk-installer.run
RUN sh /tmp/large-sdk-installer.run && rm /tmp/large-sdk-installer.run
```

Multiple directives are allowed. The context name must match `[a-z_][a-z0-9_.-]*`; context names are lowercase because Docker/BuildKit resolves `COPY --from=<name>` through image-reference-style rules on current Docker versions, and uppercase names can fail before the build with an invalid reference error. The value is passed to `docker build --build-context name=value` without shell evaluation. Local relative paths are resolved from the Dockerfile's directory and must exist before build. Remote, Git, image, and `target:` context values are passed through unchanged, for example:

<!-- readme-sample: directive-09-context-remote -->
```dockerfile
#context: base=docker-image://alpine:latest
#context: src=https://github.com/org/repo.git
```

**Caveat:** Changes to files inside named contexts do not trigger automatic rebuilds. Changing the `#context:` line itself does trigger a rebuild. Use `docker rmi <image-name>` to force a rebuild after changing only named-context contents.

### Sudo Configuration

If you need `sudo` access inside the container, use the `#sudo:` directive and make sure sudo has been installed, as in the following example:

<!-- readme-sample: directive-10-sudo -->
```dockerfile
#sudo: all
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y sudo
```

With `#sudo: all`, docker-booster creates a sudoers entry allowing passwordless sudo for the container user. Without this directive, even if sudo is installed, it won't be configured for the container user.

### GUI Applications (X11)

docker-booster can run X11 applications with minimal configuration:

```dockerfile
# X11 Application Container
#copy.home: .Xauthority
#option: -e DISPLAY
#option: -v /tmp/.X11-unix:/tmp/.X11-unix
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

**Why `#copy.home: .Xauthority`?** This securely copies only the X11 authentication file instead of mounting your entire home directory, following the principle of least privilege.

On Linux, X11 typically also requires forwarding `DISPLAY` and mounting `/tmp/.X11-unix` as shown above. Some setups instead require `--network host`, a remote X server, or Docker Desktop-specific display configuration.

## Project Structure

docker-booster is flexible about where you place your container directories. The example structure, which is in no way enforced, is:

```
my-project/
├── docker-booster/          # git submodule
│   ├── build-and-run
│   └── ...
├── containers/              # your container definitions
│   ├── build-env/
│   │   ├── Dockerfile
│   │   └── run -> ../../docker-booster/build-and-run
│   └── test-env/
│       ├── Dockerfile
│       └── run -> ../../docker-booster/build-and-run
└── src/
    └── ...
```

As long as symlinks in your docker containers point to your docker-booster/build-and-run script, it works.

**Image naming:** Each container directory name becomes the Docker image tag — `containers/build-env/` builds an image named `build-env`. It must therefore be a valid lowercase Docker image name matching `[a-z0-9][a-z0-9._-]*` (use `build-env`, not `Build_Env`); docker-booster checks this up front and exits with a clear message if the name is invalid. This is also the name to pass to `docker rmi <image-name>` when forcing a rebuild.

## Requirements

**On the host:**

- Linux or macOS with Docker and bash.
- For foreign-architecture `# platform:` builds/runs, Docker must have binfmt/QEMU support configured for the requested platform.
- GNU `tar` is optional; when unavailable, docker-booster uses a portable metadata-manifest hash for rebuild detection.
- `python3` — only when using `#http.static:`.
- Linux `ip` command from iproute2 — only when using `#http.static:` on Linux.

**In the image:**

- `/bin/sh`, `su`, and writable `/etc/passwd` and `/etc/group` — users and groups are created by appending entries directly, so no `useradd` is needed. Standard Debian, Ubuntu, Fedora and Alpine base images all qualify; scratch and distroless images do not.
- `tar` with gzip support — only when using `#copy.home:` (the files are delivered as a tarball extracted inside the container).
- `sudo` — only when using `#sudo: all`; docker-booster creates `/etc/sudoers.d/` if it is missing.

## Technical Details

- Creates a temporary user inside the container matching your host UID/GID; conflicting image user/group names get deterministic fallback names such as `${name}_${id}` and `${name}_${id}_a`
- Uses `su` for privilege de-escalation (no sudo requirement)
- Optionally configures sudoers with `#sudo: all` directive
- Preserves your working directory inside the container
- Auto-detects TTY for interactive sessions
- Always uses Docker BuildKit (the modern build path, the engine default since Docker 23.0); `RUN --mount`, cache mounts, build secrets, and named contexts work out of the box
- Automatically rebuilds the image when detecting changes in the Dockerfile's build context directory using the hash stored as a label in the Docker image. Mounted files outside that context do not trigger rebuilds by themselves.

## Security Considerations

docker-booster has **secure defaults for trusted Dockerfiles**:

- ✅ No $HOME exposure - SSH keys, GPG keys, AWS credentials stay protected
- ✅ Git-aware - automatically mounts only your repository root
- ✅ Minimal access - falls back to current directory if not in git repo

**When you need $HOME access** (e.g., for shell configurations, SSH keys):

```dockerfile
#mount: home
FROM ubuntu:22.04
```

**When you need specific files only** (most secure):

```dockerfile
#copy.home: .license.dat
#copy.home: .ssh/config
FROM ubuntu:22.04
```

The default behavior helps avoid accidental host exposure in CI/CD pipelines: nothing outside the project directory is exposed to the container unless a trusted Dockerfile or command line explicitly asks for it.

When using `#http.static:`, docker-booster briefly starts a temporary HTTP server on a random host port during the image build. Treat served directories as visible to other users on shared hosts while the build is running; serve only trusted, non-secret files.

**Trust model:** docker-booster is intended for Dockerfiles you trust — your own projects and submodules you have reviewed. Directive values are never evaluated by a shell on the host, but the directives themselves are powerful: `#option:` can pass arbitrary `docker run` flags such as `--privileged` or `-v /:/host`, `#usermount:` creates directories on the host, and `#copy.home:` copies files out of your host `$HOME`. Review the Dockerfile before running `./run` on a project you did not write.

## Testing

Run `tests/run --all` to execute the test suite. See `CLAUDE.md` for maintainer notes.

## License

MIT License - See [LICENSE](LICENSE) for details.
