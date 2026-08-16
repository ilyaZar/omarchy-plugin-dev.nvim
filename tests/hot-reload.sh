#!/bin/bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_tmp=$(mktemp -d)
trap 'rm -rf -- "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
runtime_root="$test_tmp/omarchy"
log="$test_tmp/commands.log"
mkdir -p "$stub_bin" "$runtime_root/shell"

cat >"$stub_bin/omarchy" <<'SH'
#!/bin/bash
printf 'omarchy\t%s\n' "$*" >>"$HOT_RELOAD_TEST_LOG"
SH
cat >"$stub_bin/omarchy-shell" <<'SH'
#!/bin/bash
printf 'omarchy-shell\t%s\n' "$*" >>"$HOT_RELOAD_TEST_LOG"
SH
chmod +x "$stub_bin/omarchy" "$stub_bin/omarchy-shell"

cat >"$runtime_root/shell/shell.qml" <<'QML'
Timer { onTriggered: Quickshell.reload(false) }
function rescanPlugins(): void { Quickshell.reload(false) }
QML

PATH="$stub_bin:$PATH" \
OMARCHY_PATH="$runtime_root" \
HOT_RELOAD_TEST_LOG="$log" \
  "$ROOT/scripts/hot-reload" >/dev/null

[[ $(grep -Fc $'omarchy-shell\tshell rescanPlugins' "$log") == 1 ]]
[[ $(grep -Fc $'omarchy\trestart shell' "$log" || true) == 0 ]]

: >"$log"
cat >"$runtime_root/shell/shell.qml" <<'QML'
function rescanPlugins(): void { shell.reloadPlugins() }
QML

PATH="$stub_bin:$PATH" \
OMARCHY_PATH="$runtime_root" \
HOT_RELOAD_TEST_LOG="$log" \
  "$ROOT/scripts/hot-reload" >/dev/null

[[ $(grep -Fc $'omarchy\trestart shell' "$log") == 1 ]]
[[ $(grep -Fc $'omarchy-shell\tshell rescanPlugins' "$log" || true) == 0 ]]

echo "[ok] hot reload compatibility helper"
