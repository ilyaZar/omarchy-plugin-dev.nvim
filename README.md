# omarchy-plugin-dev.nvim

[![Neovim][neovim-badge]][neovim] [![Lua][lua-badge]][lua]

A Neovim workflow for developing [Omarchy Quattro][omarchy] shell plugins
written in QML.

`omarchy-plugin-dev.nvim` lets you:

- inspect the project from a small built-in dashboard
- run validation, [qmllint][qmllint], and project tests through
  [Overseer][overseer]
- deploy and restart the shell with `<C-b>`
- test, deploy, and restart the shell with `<C-S-b>`
- run the QML language server ([qmlls][qmlls]) only inside detected Omarchy
  plugin projects

Ordinary QML projects are left alone. Opening a detected project attaches its
buffer-local mappings and language server, but never starts a build.

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
  dependencies = { "stevearc/overseer.nvim" },
  opts = {},
}
```

If you use Mason, install the QML language server with:

```vim
:MasonInstall qmlls
```

On Arch Linux, `sudo pacman -S qt6-declarative` provides both [qmlls][qmlls] and
[qmllint][qmllint].

The plugin uses an existing Overseer configuration and does not replace it.

## Usage

Open a QML file inside an Omarchy plugin project, then configure its local test
command:

```vim
:OmaDevInit
```

This runs the official Omarchy validator before creating the ignored file
`.omarchy-plugin-dev/tasks.json`. If an executable `./scripts/test` or
`./tests/all.sh` exists, choose whether to use it. For example:

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

When there is no conventional aggregate runner, initialization creates an empty
`tasks` object and opens the file instead of inventing a command. Then use
`<C-b>` while working: it validates, lints, deploys, and restarts the shell. Use
`<C-S-b>` to run the configured test before the same deploy-and-restart path.

Run `:OmaDev` to see the detected root, tool status, build behavior, and
available actions. Lightweight manifest recognition is shown separately from the
asynchronously reported result of `omarchy plugin validate`. Press `p` there to
run built-in or project-defined tasks.

## Commands

| Command            | Action                               |
| ------------------ | ------------------------------------ |
| `:OmaDev`          | Open the project dashboard           |
| `:OmaDevInit[!]`   | Configure or replace local task JSON |
| `:OmaDevTest`      | Run the configured test command      |
| `:OmaDevHotReload` | Validate, deploy, and restart once   |
| `:OmaDevRebuild`   | Test, deploy, and restart once       |
| `:OmaDevHealth`    | Run the native Neovim health check   |

## Default mappings

Mappings are normal-mode and buffer-local to detected plugin projects.

| Mapping          | Action                     |
| ---------------- | -------------------------- |
| `<C-b>`          | Check, deploy, and restart |
| `<C-S-b>`        | Test, deploy, and restart  |
| `<localleader>t` | Test                       |
| `<localleader>o` | Open the project dashboard |

Existing mappings are preserved. The plugin never changes
`vim.g.maplocalleader`.

## Configuration

The defaults work without configuration. For example:

```lua
require("omarchy_plugin_dev").setup({
  diagnostics = {
    virtual_text = false,
  },
  mappings = {
    hot_reload = "<C-b>",
    rebuild = "<C-S-b>",
    test = false,
    menu = "<localleader>o",
  },
  executables = {
    omarchy = "omarchy",
    qmllint = "auto",
    jq = "jq",
    rsync = "rsync",
  },
})
```

Set `mappings = false` to disable every default mapping. Individual mappings
also accept `false`.

See `:help omarchy-plugin-dev` for executable overrides, QML import paths, and
Overseer task overrides.

## Requirements

- Neovim 0.11 or newer
- Omarchy Quattro with `omarchy`
- [overseer.nvim][overseer]
- Qt 6 `qmllint`
- `jq` and `rsync`
- Qt `qmlls` for QML language features

The plugin prefers `/usr/lib/qt6/bin/qmllint` and accepts a `qmllint` on `PATH`
only when it reports Qt 6 or newer. An explicit `qmllint` override is honored
as-is. For language features it prefers the system Qt `qmlls`, then checks
`PATH` and Mason.

Detected plugin buffers are owned by the project-aware QML server. If another
Neovim integration automatically attaches a generic `qmlls`, it is detached from
those buffers only; ordinary QML projects remain untouched. A cache-only import
bridge exposes the configured Omarchy shell root as `qs`, allowing `qs.Commons`
and `qs.Ui` to resolve without adding `.qmlls.ini` or generated files to plugin
repositories.

Inline diagnostic text is disabled for this server by default because QML
tooling cannot fully model Omarchy's runtime-injected objects. Underlines,
signs, diagnostic pickers, and the Overseer lint quickfix list remain available.
Set `diagnostics.virtual_text = true` to restore inline text, or set
`diagnostics = false` to inherit Neovim's global diagnostic display.

## Build behavior

Both build mappings are explicit Overseer workflows. `<C-b>` runs check, deploy,
and `omarchy restart shell` as three visible steps. `<C-S-b>` inserts the
configured test before deployment. A failing or unavailable test prevents
deployment instead of being skipped. Ctrl+Shift+B also refuses to build until
`:OmaDevInit` has created a test task. A complete `tasks.rebuild` override owns
its own test policy.

The deployment helper never runs `omarchy plugin update`. The project source is
authoritative during development:

- an installed symlink to the project is preserved
- a project opened directly in its installed checkout needs no copy
- an unmanaged installed directory receives a clean staged copy
- a separate git-managed installation is refused instead of being dirtied

Every successful build restarts the shell exactly once so QML component and IPC
state cannot survive from the previous plugin generation. The manifest id stays
unchanged, so placement and settings are preserved.

## Troubleshooting

Run:

```vim
:OmaDevHealth
```

This delegates to Neovim's standard `:checkhealth omarchy-plugin-dev` report.

## Development

```bash
./scripts/test
./scripts/smoke /path/to/omarchy-plugin
stylua --check lua plugin tests
```

The smoke command validates and opens every entry point declared by the target
manifest. It uses `tests/smoke_init.lua`, a minimal configuration that loads
this checkout and an Overseer installation from Neovim's standard data
directory. Pass a second path to test against a different Neovim configuration.

[lazy]: https://github.com/folke/lazy.nvim
[lua]: https://www.lua.org/
[lua-badge]:
  https://img.shields.io/badge/Lua-5.1%2B-2C2D72?logo=lua&logoColor=white
[neovim]: https://neovim.io/
[neovim-badge]:
  https://img.shields.io/badge/Neovim-0.11%2B-57A143?logo=neovim&logoColor=white
[omarchy]: https://omarchy.org/
[overseer]: https://github.com/stevearc/overseer.nvim
[qmllint]: https://doc.qt.io/qt-6/qtqml-tooling-qmllint.html
[qmlls]: https://doc.qt.io/qt-6/qtqml-tooling-qmlls.html
