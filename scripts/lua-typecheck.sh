#!/bin/env bash

if [ -z "${VIMRUNTIME}" ]; then
    export VIMRUNTIME=$(nvim --headless --noplugin -u NONE -c "echo \$VIMRUNTIME" +qa 2>&1)
fi

echo "VIMRUNTIME: ${VIMRUNTIME}"

if [ -z "${DEPS_PATH}" ]; then
    export DEPS_PATH=${HOME}/.local/share/nvim/lazy/
fi

echo "DEPS_PATH: ${DEPS_PATH}"

lua-language-server --check=${PWD}/lua --configpath=${PWD}/.github/workflows/.luarc.json --checklevel=Information
