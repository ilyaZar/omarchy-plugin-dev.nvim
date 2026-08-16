# omarchy-plugin-dev.nvim

[![Neovim][neovim-badge]][neovim]
[![Lua][lua-badge]][lua]

A focused Neovim workflow for developing
[Omarchy Quattro][omarchy] shell plugins written in QML.

`omarchy-plugin-dev.nvim` lets you:

- validate, lint, and test a plugin through [Overseer][overseer]
- deploy and hot reload with `<C-b>`
- perform a clean rebuild with `<C-S-b>`
- use `qmlls` only inside detected Omarchy plugin projects
- inspect the project from a small built-in dashboard

Ordinary QML projects are left alone. Opening a detected project attaches its
buffer-local mappings and language server, but never starts a build or reload.

## Installation

Using [lazy.nvim][lazy]:

```lua
{
  "ilyaZar/omarchy-plugin-dev.nvim",
  main = "omarchy_plugin_dev",
  ft = { "qml" },
  cmd = {
    "OmaDev",
    "OmaDevInit",
    "OmaDevTest",
    "OmaDevHotReload",
    "OmaDevRebuild",
    "OmaDevHealth",
  },
  dependencies = {
    "stevearc/overseer.nvim",
    "mason-org/mason.nvim",
  },
  opts = {},
}
```

Install the QML language server with Mason:

```vim
:MasonInstall qmlls
```

On Arch Linux, `sudo pacman -S qt6-declarative` provides both `qmlls` and
`qmllint`.

The plugin uses an existing Overseer configuration and does not replace it.

## Usage

Open a QML file inside an Omarchy plugin project, then initialize its local
test command:

```vim
:OmaDevInit
```

This creates the ignored file `.omarchy-plugin-dev/tasks.json`:

```json
{
  "version": 1,
  "tasks": {
    "test": {
      "command": ["./scripts/test"]
    }
  }
}
```

Edit the command if needed. Then use `<C-b>` while working: it validates,
lints, deploys, and reloads the plugin. Use `<C-S-b>` when you want the full
test, deploy, and shell-restart path.

Run `:OmaDev` to see the detected root, tool status, reload mode, and available
actions.

## Commands

| Command              | Action                                |
|----------------------|---------------------------------------|
| `:OmaDev`            | Open the project dashboard            |
| `:OmaDevInit[!]`     | Initialize or replace local task JSON |
| `:OmaDevTest`        | Run the configured test command       |
| `:OmaDevHotReload`   | Validate, deploy, and reload           |
| `:OmaDevRebuild`     | Test, deploy, and restart once         |
| `:OmaDevHealth`      | Run the native Neovim health check    |

## Default mappings

Mappings are normal-mode and buffer-local to detected plugin projects.

| Mapping          | Action                         |
|------------------|--------------------------------|
| `<C-b>`          | Hot reload                     |
| `<C-S-b>`        | Clean rebuild                  |
| `<localleader>t` | Test                           |
| `<localleader>o` | Open the project dashboard     |

Existing mappings are preserved. The plugin never changes
`vim.g.maplocalleader`.

## Configuration

The defaults work without configuration. For example:

```lua
require("omarchy_plugin_dev").setup({
  mappings = {
    hot_reload = "<C-b>",
    rebuild = "<C-S-b>",
    test = false,
    menu = "<localleader>o",
  },
  restart = {
    mode = "auto", -- auto, soft, or restart
  },
})
```

Set `mappings = false` to disable every default mapping. Individual mappings
also accept `false`.

See `:help omarchy-plugin-dev` for executable overrides, QML import paths, and
reload configuration.

## Requirements

- Neovim 0.11 or newer
- Omarchy Quattro with `omarchy` and `omarchy-shell`
- [overseer.nvim][overseer]
- `qmllint`, `jq`, and `rsync`
- `qs` for detecting live reload support
- Qt `qmlls` for QML language features

The plugin looks for `qmlls` on `PATH`, in Arch's Qt installation, and in
Mason.

## Reload behavior

Hot reload validates and lints the source, stages a clean copy, deploys it to
the Omarchy plugin directory, and asks the running shell to replace the
plugin. It falls back to one shell restart when live reload is unavailable.

Clean rebuild also runs the configured test and always restarts the shell
exactly once. The manifest id remains unchanged, so placement and settings are
preserved.

## Troubleshooting

Run:

```vim
:OmaDevHealth
```

This delegates to Neovim's standard `:checkhealth omarchy-plugin-dev` report.

## Development

```bash
./scripts/test
./scripts/smoke /path/to/omarchy-plugin /path/to/nvim/init.lua
stylua --check lua plugin tests
```

[lazy]: https://github.com/folke/lazy.nvim
[lua]: https://www.lua.org/
[lua-badge]: https://img.shields.io/badge/Lua-5.1%2B-2C2D72?logo=lua&logoColor=white
[neovim]: https://neovim.io/
[neovim-badge]: https://img.shields.io/badge/Neovim-0.11%2B-57A143?logo=neovim&logoColor=white
[omarchy]: https://omarchy.org/
[overseer]: https://github.com/stevearc/overseer.nvim
