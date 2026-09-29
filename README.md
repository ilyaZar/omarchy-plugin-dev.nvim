# omarchy-plugin-dev.nvim

[![Neovim][neovim-badge]][neovim] [![Lua][lua-badge]][lua] [![CI][ci-badge]][ci]

A Neovim workflow for developing [Omarchy Quattro][omarchy] shell plugins
written in QML.

- inspect projects from a built-in dashboard
- validate, lint with [qmllint][qmllint], and run tests through
  [Overseer][overseer]
- deploy and restart the shell, optionally running tests first
- configure [qmlls][qmlls] with Omarchy imports and format QML on save

Supports QML and JavaScript libraries marked with `.pragma library` (`qmljs`).
Editor integration attaches only inside detected Omarchy plugin projects.
Opening a file never starts a build.

## Installation

Requires Neovim 0.11+, Omarchy Quattro, [overseer.nvim][overseer], Qt 6
`qmllint`, `jq`, and `rsync`. Language support and formatting also need
`qmlls`; shell logs use `journalctl`.

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

The plugin uses an existing Overseer configuration and does not replace it.

## Usage

Open a QML file in an Omarchy plugin project and use `<C-b>` to check, deploy,
and restart the shell. No task configuration is needed for this workflow.

To configure tests, run `:OmaDevInit`. It validates the project and creates
`.omarchy-plugin-dev/task-config.json`, adding its directory to `.gitignore`.
Choose an executable `./scripts/test` or `./tests/all.sh` when offered;
otherwise, initialization opens an empty task configuration for you to edit.
See the [task configuration example][help] or
`:help omarchy-plugin-dev-initialization`.

Legacy `tasks.json` files remain readable; see the initialization help for
replacement with `:OmaDevInit!`.

Open `:OmaDev` for project and tool status. Press `p` for built-in tasks,
custom tasks, or **Shell logs**. Run `:OmaDevHealth` to diagnose missing tools.

## Commands and mappings

| Command            | Default key      | Action                          |
| ------------------ | ---------------- | ------------------------------- |
| `:OmaDev`          | `<localleader>o` | Open the project dashboard      |
| `:OmaDevInit[!]`   |                  | Configure or replace task JSON  |
| `:OmaDevTest`      | `<localleader>t` | Run the configured test command |
| `:OmaDevHotReload` | `<C-b>`          | Check, deploy, and restart      |
| `:OmaDevBuild`     | `<C-S-b>`        | Check, test, deploy, restart    |
| `:OmaDevHealth`    |                  | Run the Neovim health check     |

Mappings are normal-mode and buffer-local to detected plugin projects. Existing
`<localleader>` mappings are preserved; build shortcuts take precedence. The
plugin never changes `vim.g.maplocalleader`.

## Build behavior

Checks validate the manifest and lint QML. The default build also requires
a configured test. Failed checks or tests stop deployment. Successful builds
restart the shell once.

- Working directly in the installed plugin, or through a symlink to your
  project, requires no copying.
- Otherwise, deployment copies your plugin files into the installation.
  Files removed from your project or excluded from deployment are also
  removed from the installed copy.
- Deployment refuses to overwrite a separate Git checkout or a symlink to
  another project.

Deployment enables the plugin by default. Set `enable_auto = false` to enable
it only on first installation. Set `enable_first_install = false` as well
to manage enabling yourself.

## Configuration

The defaults work with `opts = {}`. To disable format-on-save and show inline
diagnostics, change `opts` in the installation example:

```lua
opts = {
  format_on_save = false,
  diagnostics = { virtual_text = true },
},
```

Plugin QML uses four-space indentation and formats on save through `qmlls`.
QML JavaScript (`qmljs`) keeps language support and diagnostics, but skips
the plugin's format-on-save hook to avoid qmlls timeouts. It sets
`b:autoformat=false` for other save hooks that honor that convention.
Inline diagnostic text is off by default; signs, underlines, and diagnostic
pickers remain available. Set `diagnostics = false` to use Neovim's global
settings.

Change shortcuts in `opts.mappings`; set an entry or `mappings` to `false`
to disable it.

In `:OmaDev`, press `c` for plugin settings. To open your Lua config instead
of help, add `config_file = "lua/plugins/omarchy-plugin-dev.lua"` to `opts`.
Use your file's path, relative to Neovim's config directory or absolute.
Restart Neovim after changing keys.

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

[ci]: https://github.com/ilyaZar/omarchy-plugin-dev.nvim/actions/workflows/check.yml
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
