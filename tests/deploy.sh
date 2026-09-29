#!/bin/bash
set -euo pipefail

test_root=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/omarchy-plugin-dev-test.XXXXXX")
cleanup() {
  rm -rf -- "$test_root"
}
trap cleanup EXIT

project="$test_root/project"
plugins="$test_root/plugins"
mkdir -p "$project/.omarchy-plugin-dev" "$project/ignored"

printf '%s\n' 'import QtQuick' 'Item {}' >"$project/Service.qml"
printf '%s\n' \
  '{"schemaVersion":1,"id":"dev.deploy-test","name":"Deploy Test","version":"1","kinds":["service"],"entryPoints":{"service":"Service.qml"}}' \
  >"$project/manifest.json"
printf '%s\n' '{}' >"$project/.omarchy-plugin-dev/task-config.json"
printf '%s\n' '.omarchy-plugin-dev/' 'ignored/' >"$project/.gitignore"
ln -s -- ../Service.qml "$project/ignored/Service.qml"
git -C "$project" init --quiet
git -C "$project" add .gitignore Service.qml manifest.json
printf '%s\n' 'import QtQuick' 'Item { objectName: "untracked" }' >"$project/Extra.qml"

OMARCHY_PLUGINS_DIR="$plugins" ./scripts/deploy --dry-run "$project" >/dev/null
[[ ! -e $plugins/dev.deploy-test ]] || {
  printf '[error] dry run created the plugin target\n' >&2
  exit 1
}

OMARCHY_PLUGINS_DIR="$plugins" ./scripts/deploy --apply "$project" >"$test_root/deploy.out"
[[ -f $plugins/dev.deploy-test/Service.qml ]]
rg -Fq 'Preparing validated deployment' "$test_root/deploy.out"
rg -Fq 'plugin validate' "$test_root/deploy.out"
rg -Fq 'Prepared validated plugin copy' "$test_root/deploy.out"
rg -Fq 'Installing plugin files' "$test_root/deploy.out"
rg -Fq 'stage tracked and non-ignored project files' "$test_root/deploy.out"
rg -Fq 'Installed plugin files: dev.deploy-test' "$test_root/deploy.out"
if rg -Fqi restart "$test_root/deploy.out"; then
  printf '[error] deployment output claims responsibility for restarting the shell\n' >&2
  exit 1
fi
[[ -f $plugins/dev.deploy-test/Extra.qml ]]
[[ ! -e $plugins/dev.deploy-test/.omarchy-plugin-dev ]]
[[ ! -e $plugins/dev.deploy-test/ignored ]]

printf '%s\n' stale >"$plugins/dev.deploy-test/stale.txt"
printf '%s\n' 'import QtQuick' 'Item { objectName: "updated" }' >"$project/Service.qml"
OMARCHY_PLUGINS_DIR="$plugins" ./scripts/deploy --apply "$project" >/dev/null
rg -Fq 'objectName: "updated"' "$plugins/dev.deploy-test/Service.qml"
[[ ! -e $plugins/dev.deploy-test/stale.txt ]]

rm -rf -- "$plugins/dev.deploy-test"
ln -s -- "$project" "$plugins/dev.deploy-test"
OMARCHY_PLUGINS_DIR="$plugins" ./scripts/deploy --apply "$project" >/dev/null
[[ -L $plugins/dev.deploy-test ]]
[[ $(realpath -- "$plugins/dev.deploy-test") == $(realpath -- "$project") ]]

rm -f -- "$plugins/dev.deploy-test"
mkdir -p "$plugins/dev.deploy-test/.git"
printf '%s\n' preserved >"$plugins/dev.deploy-test/local.txt"
if OMARCHY_PLUGINS_DIR="$plugins" ./scripts/deploy --apply "$project" \
  >"$test_root/git-checkout.out" 2>"$test_root/git-checkout.err"; then
  printf '[error] deployment overwrote a separate git checkout\n' >&2
  exit 1
fi
rg -Fq 'separate git checkout' "$test_root/git-checkout.err"
rg -Fq preserved "$plugins/dev.deploy-test/local.txt"

mock_bin="$test_root/mock-bin"
enable_log="$test_root/enable.log"
enable_attempt_log="$test_root/enable-attempt.log"
ping_log="$test_root/ping.log"
rescan_log="$test_root/rescan.log"
mkdir -p "$mock_bin"
printf '%s\n' '#!/bin/bash' \
  'set -euo pipefail' \
  'if [[ $1 == plugin && $2 == validate ]]; then exit 0; fi' \
  'if [[ $1 == plugin && $2 == list ]]; then printf '\''[{"id":"dev.deploy-test"}]\n'\''; exit 0; fi' \
  'if [[ $1 == plugin && $2 == enable ]]; then' \
  '  printf '\''enable\n'\'' >>"$ENABLE_ATTEMPT_LOG"' \
  '  [[ $(wc -l <"$ENABLE_ATTEMPT_LOG") -ge 3 ]]' \
  '  printf '\''%s\n'\'' "$3" >>"$ENABLE_LOG"' \
  '  exit 0' \
  'fi' \
  'exit 1' >"$mock_bin/omarchy"
printf '%s\n' '#!/bin/bash' \
  'set -euo pipefail' \
  'if [[ $1 == shell && $2 == ping ]]; then' \
  '  printf '\''ping\n'\'' >>"$PING_LOG"' \
  '  [[ $(wc -l <"$PING_LOG") -ge 3 ]]' \
  '  exit' \
  'fi' \
  'if [[ $1 == shell && $2 == rescanPlugins ]]; then' \
  '  printf '\''rescan\n'\'' >>"$RESCAN_LOG"' \
  '  [[ $(wc -l <"$RESCAN_LOG") -ge 3 ]]' \
  'fi' >"$mock_bin/omarchy-shell"
chmod +x "$mock_bin/omarchy" "$mock_bin/omarchy-shell"

rm -rf -- "$plugins/dev.deploy-test"
deploy_env=(
  "ENABLE_LOG=$enable_log"
  "ENABLE_ATTEMPT_LOG=$enable_attempt_log"
  "PING_LOG=$ping_log"
  "RESCAN_LOG=$rescan_log"
  "OMARCHY_PLUGIN_DEV_OMARCHY=$mock_bin/omarchy"
  "OMARCHY_PLUGIN_DEV_OMARCHY_SHELL=$mock_bin/omarchy-shell"
)
env "${deploy_env[@]}" OMARCHY_PLUGINS_DIR="$plugins" \
  ./scripts/deploy --apply --enable-first-install "$project" >/dev/null
[[ $(wc -l <"$enable_log") -eq 1 ]]
[[ $(wc -l <"$enable_attempt_log") -eq 3 ]]
[[ $(wc -l <"$ping_log") -eq 3 ]]

env "${deploy_env[@]}" OMARCHY_PLUGINS_DIR="$plugins" \
  ./scripts/deploy --apply --enable-first-install "$project" >/dev/null
[[ $(wc -l <"$enable_log") -eq 1 ]]

env "${deploy_env[@]}" OMARCHY_PLUGINS_DIR="$plugins" \
  ./scripts/deploy --apply --enable-auto --enable-first-install "$project" >"$test_root/enable.out"
[[ $(wc -l <"$enable_log") -eq 2 ]]
[[ $(wc -l <"$enable_attempt_log") -eq 4 ]]
[[ $(wc -l <"$rescan_log") -eq 4 ]]
rg -Fq 'Enabling plugin' "$test_root/enable.out"
rg -Fq 'shell ping' "$test_root/enable.out"
rg -Fq 'shell rescanPlugins' "$test_root/enable.out"
rg -Fq 'plugin list --json' "$test_root/enable.out"
rg -Fq 'plugin enable dev.deploy-test' "$test_root/enable.out"
rg -Fq 'Enabled plugin: dev.deploy-test' "$test_root/enable.out"

printf '[ok] deployment helper\n'
