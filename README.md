# omarchy-plugin-dev.nvim

[![Neovim][neovim-badge]][neovim] [![Lua][lua-badge]][lua] [![CI][ci-badge]][ci]
[![Lua coverage][coverage-badge]][coverage]

A Neovim workflow for developing [Omarchy Quattro][omarchy] shell plugins
written in QML.

- inspect projects from a built-in dashboard
- validate, lint with [qmllint][qmllint], and run tests through
  [Overseer][overseer]
- select a local folder, symlink, or Git checkout and build there
- configure [qmlls][qmlls] with Omarchy imports and format QML on save

Supports QML and JavaScript libraries marked with `.pragma library` (`qmljs`).
Editor integration attaches only inside detected Omarchy plugin projects.

## Installation

Requires Neovim 0.11+, Omarchy Quattro, [overseer.nvim][overseer], Qt 6
`qmllint`, `jq`, `rsync`, Git, and util-linux (`flock`, `findmnt`). Language
support also needs `qmlls`;
shell logs use `journalctl`.

Add this [lazy.nvim][lazy] spec to your Neovim plugin configuration:

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
    "OmaDevBuild",
    "OmaDevHealth",
  },
  dependencies = { "stevearc/overseer.nvim" },
  opts = {
    mappings = {
      hot_reload = "<C-b>",
      build = "<C-S-b>",
      test = "<localleader>t",
      menu = "<localleader>o",
    },
  },
}
```

If you use Mason, install the QML language server with:

```vim
:MasonInstall qmlls
```

Omarchy installs `qt6-declarative` by default through Quickshell. On other Arch
Linux systems, `sudo pacman -S qt6-declarative` provides [qmlls][qmlls],
[qmllint][qmllint], and `qmlformat`.

The plugin uses an existing Overseer configuration, if you've set up one
already.

## Usage

Open a QML file in an Omarchy plugin project and run `:OmaDevInit`. This creates
`.omarchy-plugin-dev/task-config.json` with two local targets, adding its
directory to `.gitignore`. Choose a test runner when offered, or
configure tests later. Initialization does not install the plugin or run tests.

In `:OmaDev`, select **Local link** to point Omarchy at your checkout.
Use **Local project** if Omarchy already uses it. `<C-b>` checks and restarts;
`<C-S-b>` also runs that target's tests. Builds never clone, relink, or copy
files; preparation happens only when you select a target.

Open `:OmaDev` for **Build**, **Status**, and **Settings**. Press `r` to refresh
project/tool information and rerun validation, or `p` to choose built-in tasks,
custom tasks, or **Shell logs**. Run `:OmaDevHealth` to diagnose missing tools.

Build's **Sources** section lists named targets from `task-config.json`. Names
and order are yours. A useful set is:

| Name          | Type           | Purpose                         |
|---------------|----------------|---------------------------------|
| Local project | `local-source` | Build an existing checkout      |
| Local link    | `symlink`      | Point Omarchy at your checkout  |
| Upstream      | `git-clone`    | Clone the default branch once   |
| Pinned        | `git-clone`    | Clone a tag or full commit once |

See the [complete JSON example](examples/task-config.json), which uses
keyboard-layout, and `:help omarchy-plugin-dev-sources`. Adapt its repository,
plugin ID, and tag to your project. `description` fields explain the variants;
JSON does not support comments.

Press `e` to edit the file. Saved edits take effect on refresh, selection, and
build without restarting Neovim. The star marks the selected installed target,
not runtime health. The parent task card shows the actual build directory and
revision. Old configuration formats are rejected; recreate them with
`:OmaDevInit!` rather than keeping a second sources file.

## Commands and mappings

| Command            | Default key      | Action                          |
| ------------------ | ---------------- | ------------------------------- |
| `:OmaDev`          | `<localleader>o` | Open the project dashboard      |
| `:OmaDevInit[!]`   |                  | Configure or replace task JSON  |
| `:OmaDevTest`      | `<localleader>t` | Run the configured test command |
| `:OmaDevHotReload` | `<C-b>`          | Check target and restart        |
| `:OmaDevBuild`     | `<C-S-b>`        | Check target, test, restart     |
| `:OmaDevHealth`    |                  | Run the Neovim health check     |

Mappings are normal-mode and buffer-local to detected plugin projects. Existing
`<localleader>` mappings are preserved; build shortcuts take precedence. The
plugin never changes `vim.g.maplocalleader`.

## Build behavior

Checks validate the manifest and lint QML at the selected destination. Each
entry has its own `tasks` object. A test definition uses `command` argv and an
optional `description`; `"test": false` explicitly disables it. An omitted test
shows the existing missing-test warning. Detected scripts never run
without configuration.
Configured failures and missing executables stop the workflow before restart.
Test detection skips Git-ignored files and deleted tests.

Build-and-restart requires Omarchy's installed path to resolve to that same
folder. The editor project's configuration supplies commands; downloaded task
files are never loaded. Switching cannot interrupt an active build.

A matching destination is reused without fetching or resetting. Selecting the
active row changes nothing. Replacing a Git checkout requires confirmation,
including when clean, and permanently deletes it without a backup. A link is
removed without deleting its target. Local sources are never deleted.

Selection preserves enabled state and settings; enable a new plugin explicitly
with `omarchy plugin enable <id>`. Omarchy's updater can modify linked checkouts
and tagged Git clones: they are not update-proof.

## Configuration

The defaults work with `opts = {}`. To disable format-on-save and show inline
diagnostics, change `opts` in the installation example:

```lua
opts = {
  format_on_save = false,
  diagnostics = { virtual_text = true },
},
```

Plugin QML uses four-space indentation and formats on save through `qmlls`. QML
JavaScript (`qmljs`) keeps language support and diagnostics, but skips the
plugin's format-on-save hook to avoid qmlls timeouts. It sets
`b:autoformat=false` for other save hooks that honor that convention. Inline
diagnostic text is off by default; signs, underlines, and diagnostic pickers
remain available. Set `diagnostics = false` to use Neovim's global settings.

Change shortcuts in `opts.mappings`; set an entry or `mappings` to `false` to
disable it.

In `:OmaDev`, press `c` for plugin settings. To open your Lua config instead of
help, add `config_file = "lua/plugins/omarchy-plugin-dev.lua"` to `opts`. Use
your file's path, relative to Neovim's config directory or absolute. Restart
Neovim after changing keys.

The task panel opens at one-third height with equal task-list and output panes.
Change `opts.task_layout.height` or `list_width` to fractions such as `0.15`.
Sizes apply only on opening; manual resizing is preserved until you close the
panel. Set `task_layout = false` to keep Overseer's own layout.

For mixed repositories, `qml_file_filter` selects which files receive plugin
integration. See [the help file][help] or `:help omarchy-plugin-dev` for its
callback, executable and import-path settings, and task overrides.

## Development

```bash
./scripts/test
./scripts/smoke /path/to/omarchy-plugin
stylua --check ftdetect lua plugin tests
```

See [contributor notes](CONTRIBUTING.md) for smoke-test setup.

## License

[MIT](LICENSE) © 2026 IlyaZar.

[coverage]: https://app.codecov.io/gh/ilyaZar/omarchy-plugin-dev.nvim
[coverage-badge]:
  https://img.shields.io/codecov/c/github/ilyaZar/omarchy-plugin-dev.nvim/main?flag=lua&style=flat-square&logo=codecov&logoColor=white&label=lua%20coverage&labelColor=2e3440&color=F01F7A
[ci]:
  https://github.com/ilyaZar/omarchy-plugin-dev.nvim/actions/workflows/check.yml
[ci-badge]:
  https://img.shields.io/github/actions/workflow/status/ilyaZar/omarchy-plugin-dev.nvim/check.yml?branch=main&label=CI&logo=githubactions&logoColor=white
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
[help]: doc/omarchy-plugin-dev.txt
