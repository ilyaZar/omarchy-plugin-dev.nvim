# Contributor notes

Run `./scripts/test` for automated checks and
`stylua --check ftdetect lua plugin tests` for Lua formatting.
Run `./scripts/check-lua` with LuaLS on PATH for type diagnostics.
The target backend checks use Python 3's standard library, Git, jq, rsync,
and util-linux. They use temporary local repositories and stub Omarchy
commands; no running desktop or network access is needed.

For Lua line coverage, install LuaCov 0.17.0 and LuaFileSystem 1.8.0 for
Lua 5.1, then run `./scripts/test --coverage`. The report is written to
`coverage/luacov.report.out`. It includes unexecuted plugin Lua files and
excludes tests, dependencies, and shell scripts. CI uploads this report to
Codecov from the current Neovim job using GitHub OIDC.

The smoke test requires an existing Omarchy plugin project and validates and
opens every entry point declared by its manifest:

```bash
./scripts/smoke /path/to/omarchy-plugin
```

It uses `tests/smoke_init.lua`, a minimal configuration that loads this
checkout and an Overseer installation from Neovim's standard data directory.
Pass a second path to test against a different Neovim initialization file:

```bash
./scripts/smoke /path/to/omarchy-plugin /path/to/init.lua
```

The smoke runner uses headless Neovim. Temporary project copies are created
under the user's cache directory and sent to the trash with `gio` when
available. If cleanup cannot move them to the trash, the script reports their
location.
