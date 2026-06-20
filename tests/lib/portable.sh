#!/bin/sh

stat_uid() {
    if stat -c %u "$1" >/dev/null 2>&1; then
        stat -c %u "$1"
    else
        stat -f %u "$1"
    fi
}

run_with_pty() {
    if script -q -c true /dev/null >/dev/null 2>&1; then
        script -q -c "$*" /dev/null
    else
        script -q /dev/null "$@"
    fi
}

is_docker_desktop_host_network() {
    [ "$(uname -s)" = "Darwin" ] || return 1
    docker info --format '{{.OperatingSystem}}' 2>/dev/null | grep -qi 'docker desktop'
}
