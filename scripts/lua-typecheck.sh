#!/usr/bin/env bash
set -e

# This script performs a Lua typecheck, with different behaviors for local and CI environments.
#
# It supports two local modes:
# 1. Default (Managed): Downloads all dependencies into a project-local ./target/deps directory.
# 2. --live: Uses the system's installed `nvim` and `lua-language-server`. It does not
#    manage plugin dependencies, assuming the user has them configured.

verbose=false

log() {
    echo "$1" >&2
}

log_verbose() {
    if [ "$verbose" = "true" ]; then
        echo "$1" >&2
    fi
}

die() {
    echo "Error: $1" >&2
    exit 1
}

handle_live_mode() {
    export DEPS_PATH="$HOME/.local/share/nvim/lazy"
    log_verbose "Setting DEPS_PATH for live mode to: $DEPS_PATH"

    command -v nvim &>/dev/null || die "nvim command not found. Please install Neovim."

    if command -v lua-language-server &>/dev/null; then
        log_verbose "Found lua-language-server in PATH."
    else
        log_verbose "lua-language-server not found in PATH. Checking Mason..."
        local mason_luals_path="$HOME/.local/share/nvim/mason/bin/lua-language-server"
        if [ -x "$mason_luals_path" ]; then
            log_verbose "Found lua-language-server in Mason packages."
            export PATH="$HOME/.local/share/nvim/mason/bin:$PATH"
        else
            die "lua-language-server not found in PATH or in Mason packages. Please install it."
        fi
    fi

    # $VIMRUNTIME is not supposed to be expanded below
    # shellcheck disable=SC2016
    VIMRUNTIME="$(nvim --headless --noplugin -u NONE -c 'echo $VIMRUNTIME' +qa 2>&1)"
    export VIMRUNTIME
}

manage_plugin_dependencies() {
    local deps_dir=$1
    local setup_deps_flags=$2
    log "Cloning/updating dependencies to $deps_dir..."
    ./scripts/setup-deps.sh "$setup_deps_flags" clone "$deps_dir"
    export DEPS_PATH="$deps_dir"
    log_verbose "Set DEPS_PATH to $DEPS_PATH"
}

run_typechecker() {
    local config_path=$1
    if [ -z "$VIMRUNTIME" ]; then
        die "VIMRUNTIME is not set. Cannot proceed."
    fi
    if [ -z "$config_path" ]; then
        die "Luarc config path is not set. Cannot proceed."
    fi
    command -v lua-language-server &>/dev/null || die "lua-language-server not found in PATH."

    log "Running Lua typechecker..."
    lua-language-server --check="$PWD/lua" \
        --loglevel=trace \
        --configpath="$config_path" \
        --checklevel=Information
    log_verbose "Typecheck complete."
}

main() {
    local dest_dir="$PWD/target/tests"
    local luarc_path="$dest_dir/luarc.json"
    local mode="managed"
    local setup_deps_flags=""

    for arg in "$@"; do
        case $arg in
            --live)
            mode="live"
            shift
            ;;
            --verbose|-v)
            verbose=true
            setup_deps_flags="--verbose"
            shift
            ;;
        esac
    done

    if [ "$GITHUB_ACTIONS" = "true" ]; then
        mode="ci"
        # Always be verbose in CI
        setup_deps_flags="--verbose"
    fi

    log "mode: $mode"

    if [ "$mode" == "live" ]; then
        handle_live_mode
    else
        log "Setting up environment in: $dest_dir"
        mkdir -p "$dest_dir"

        if [ "$mode" == "managed" ]; then
            log "Installing nvim runtime..."
            VIMRUNTIME="$(./scripts/setup-deps.sh "$setup_deps_flags" install-nvim "$dest_dir")"
            export VIMRUNTIME
            log_verbose "Installed nvim runtime at: $VIMRUNTIME"
        fi

        log "Installing lua-language-server..."
        local luals_bin_path
        luals_bin_path="$(./scripts/setup-deps.sh "$setup_deps_flags" install-luals "$dest_dir")"
        export PATH="$luals_bin_path:$PATH"
        log_verbose "Added $luals_bin_path to PATH"

        local deps_dir="$dest_dir/deps"
        log "Cloning/updating dependencies to $deps_dir..."
        ./scripts/setup-deps.sh "$setup_deps_flags" clone "$deps_dir"
        export DEPS_PATH="$deps_dir"
        log_verbose "Set DEPS_PATH to $DEPS_PATH"
    fi

    ./scripts/setup-deps.sh $setup_deps_flags generate-luarc "$luarc_path"

    log "VIMRUNTIME: $VIMRUNTIME"
    log "DEPS_PATH: $DEPS_PATH"

    run_typechecker "$luarc_path"
}

main "$@"
