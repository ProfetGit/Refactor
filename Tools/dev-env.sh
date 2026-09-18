#!/bin/sh
# Prefer a project-local toolchain; system tools work in CI and normal installations.
if [ -d .tools/bin ]; then
    PATH="$PWD/.tools/bin:$PATH"
    export PATH
    # A tree built elsewhere and copied in has wrappers pointing at a directory that is
    # gone, so fall back to the paths the tree layout implies rather than failing silently.
    if luarocks --tree="$PWD/.tools" path >/dev/null 2>&1; then
        eval "$(luarocks --tree="$PWD/.tools" path)"
    else
        LUA_PATH="$PWD/.tools/share/lua/5.1/?.lua;$PWD/.tools/share/lua/5.1/?/init.lua;;"
        LUA_CPATH="$PWD/.tools/lib/lua/5.1/?.so;;"
        export LUA_PATH LUA_CPATH
    fi
fi
exec "$@"
