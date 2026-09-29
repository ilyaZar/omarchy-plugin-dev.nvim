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
- format plugin QML on save with Qt's official conventions

Ordinary QML projects are left alone. Opening a detected project attaches its
buffer-local mappings and language server, but never starts a build.

JavaScript library files beginning with `.pragma library` are recognized as
`qmljs`, so Qt's language server and linter handle them instead of generic
TypeScript tooling.

## Installation

Using [lazy.nvim][lazy]:

```lua
{
  "ilyaZar/omarchy-plugin-dev.nvim",
  main = "omarchy-plugin-dev",
  ft = { "qml", "qmljs" },
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

Omarchy installs `qt6-declarative` by default through Quickshell. On other Arch
Linux systems, `sudo pacman -S qt6-declarative` provides [qmlls][qmlls],
[qmllint][qmllint], and `qmlformat`.

The plugin uses an existing Overseer configuration and does not replace it.

## Usage

Open a QML file inside an Omarchy plugin project, then configure its local test
command:

```vim
:OmaDevInit
```

This runs the official Omarchy validator before creating the ignored file
`.omarchy-plugin-dev/task-config.json`. If an executable `./scripts/test` or
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
`tasks` object and opens the file instead of inventing a command. Legacy
`.omarchy-plugin-dev/tasks.json` files remain readable; `:OmaDevInit!` replaces
one with `task-config.json`. Then use `<C-b>` while working: it validates,
lints, deploys, and restarts the shell. Use `<C-S-b>` to run the configured test
before the same deploy-and-restart path.

Run `:OmaDev` to see the detected root, tool status, build behavior, and
available actions. Lightweight manifest recognition is shown separately from the
asynchronously reported result of `omarchy plugin validate`. Press `p` there to
run built-in or project-defined tasks.

## Commands and mappings

| Command            | Default key      | Action                           |
| ------------------ | ---------------- | -------------------------------- |
| `:OmaDev`          | `<localleader>o` | Open the project dashboard       |
| `:OmaDevInit[!]`   |                  | Configure or replace task JSON   |
| `:OmaDevTest`      | `<localleader>t` | Run the configured test command  |
| `:OmaDevHotReload` | `<C-b>`          | Check, deploy, and restart       |
| `:OmaDevRebuild`   | `<C-S-b>`        | Check, test, deploy, and restart |
| `:OmaDevHealth`    |                  | Run the Neovim health check      |

Mappings are normal-mode and buffer-local to detected plugin projects. Existing
`<localleader>` mappings are preserved; build shortcuts take precedence. The
plugin never changes `vim.g.maplocalleader`.

## Configuration

The defaults work without configuration. For example:

```lua
require("omarchy-plugin-dev").setup({
  diagnostics = {
    virtual_text = false,
  },
  enable_auto = true,
  enable_first_install = true,
  format_on_save = true,
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

`enable_auto` enables every deployment. If disabled, `enable_first_install`
enables only a new installation.

Detected plugin QML uses four-space indentation and is formatted on save by
default. This enforces Qt's [QML Coding Conventions][qml-conventions] through
its [QML formatter][qmlformat], whose default indentation is four spaces. Set
`format_on_save = false` to opt out.

Set `mappings = false` to disable every default mapping. Individual mappings
also accept `false`.

Mixed repositories can set `qml_file_filter` to decide whether a QML or QML
JavaScript file belongs to the detected Omarchy plugin. The callback receives
`path`, `relative_path`, `root`, and a copy of the validated `manifest`, and
must return a boolean. Returning `false` leaves that file's LSP, formatting,
mappings, and built-in linting to other tooling. Without a callback, ordinary
files below the plugin root retain the default behavior. The plugin does not
guess foreign project markers or target layouts.

In a Git working tree, built-in lint discovery includes tracked and new
nonignored QML sources while leaving ignored artifacts alone. Non-Git projects
fall back to recursive source discovery.

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
Neovim integration automatically attaches a generic `qmlls`, it is detached
from those buffers only; ordinary QML projects remain untouched. After
attachment settles, a detached competing client is stopped only when it owns
no other buffers. If graceful shutdown does not end its process, the process is
terminated after a short grace period. A cache-only
import bridge exposes the configured Omarchy shell root as `qs`. Qt's QML
module path is discovered from its Qt 6 tools. This resolves Qt and Omarchy
imports without adding `.qmlls.ini` or generated files to plugin repositories.
The bridge gives grouped `Style` and `Color` objects concrete tooling types
and exposes the documented `PluginBarApi` type for `Panel.bar` without
changing the installed shell. Valid host members remain quiet while
misspellings are still reported. Because ordinary Omarchy plugins
have no CMake build, the server's automatic CMake discovery is disabled.

Inline diagnostic text is disabled for this server by default because QML
tooling cannot fully model every Omarchy runtime-injected object. Underlines,
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
stylua --check ftdetect lua plugin tests
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
[qml-conventions]: https://doc.qt.io/qt-6/qml-codingconventions.html
[qmlformat]: https://doc.qt.io/qt-6/qtqml-tooling-qmlformat.html
[qmllint]: https://doc.qt.io/qt-6/qtqml-tooling-qmllint.html
[qmlls]: https://doc.qt.io/qt-6/qtqml-tooling-qmlls.html
