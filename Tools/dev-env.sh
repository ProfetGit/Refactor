#!/bin/sh
# Prefer a project-local toolchain; system tools work in CI and normal installations.
if [ -d .tools/bin ]; then
    PATH="$PWD/.tools/bin:$PATH"
    export PATH
    eval "$(luarocks --tree="$PWD/.tools" path)"
fi
exec "$@"
