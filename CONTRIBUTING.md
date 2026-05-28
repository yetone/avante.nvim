# CONTRIBUTING

Contributions to avante.nvim are welcome! If you're interested in helping out, please feel free to submit pull requests or open issues. Before contributing, ensure that your code has been thoroughly tested.

## Set up the development environment:

## With nix

Running `nix develop` will give you a shell with all dependencies.

## Other systems

1. Install [StyLua](https://github.com/JohnnyMorganz/StyLua) for Lua code formatting.
2. Install [pre-commit](https://pre-commit.com) for managing and maintaining pre-commit hooks.
3. After cloning the repository, run the following command to set up pre-commit hooks:

```sh
pre-commit install --install-hooks
```

## Tooling configuration

For setting up lua_ls you can use the following for `nvim-lspconfig`:

```lua
lua_ls = {
  settings = {
    Lua = {
      runtime = {
        version = "LuaJIT",
        special = { reload = "require" },
      },
      workspace = {
        library = {
          vim.fn.expand "$VIMRUNTIME/lua",
          vim.fn.expand "$VIMRUNTIME/lua/vim/lsp",
          vim.fn.stdpath "data" .. "/lazy/lazy.nvim/lua/lazy",
        },
      },
    },
  },
},
```

You can also use the following config for `lazydev.nvim`:

```lua
      {
        "folke/lazydev.nvim",
        ft = "lua",
        cmd = "LazyDev",
        opts = {
          dependencies = {
            -- Manage libuv types with lazy. Plugin will never be loaded
            { "Bilal2453/luvit-meta", lazy = true },
          },
          library = {
            { path = "~/workspace/avante.nvim/lua", words = { "avante" } },
            { path = "luvit-meta/library", words = { "vim%.uv" } },
          },
        },
      },
```

Then you can set `dev = true` in your `lazy` config for development.

# How to run the tests ?

The infra attempts by default to setup everything in "--managed" mode.

```
make lint
make lua-typecheck
make luatest
```

If the previous doesn't work you can check the Makefile targets and run the files in scripts/ with `--live` instead.
