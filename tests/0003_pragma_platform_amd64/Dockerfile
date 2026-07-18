# platform: amd64
# alpine:3.22 is reserved for the platform tests (0002-0004): an explicit
# --platform pull retags the base in the shared store, and pulling into
# alpine:latest would leak a foreign-arch image into every later test.
# See the matching rmi in tests/run cleanup().
FROM alpine:3.22
