#!/bin/bash
set -euo pipefail

test_root=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/omarchy-plugin-dev-test.XXXXXX")
cleanup() {
  rm -rf -- "$test_root"
}
trap cleanup EXIT

project="$test_root/project"
plugins="$test_root/plugins"
mkdir -p "$project/.omarchy-plugin-dev"

printf '%s\n' 'import QtQuick' 'Item {}' >"$project/Service.qml"
printf '%s\n' \
  '{"schemaVersion":1,"id":"dev.deploy-test","name":"Deploy Test","version":"1","kinds":["service"],"entryPoints":{"service":"Service.qml"}}' \
  >"$project/manifest.json"
printf '%s\n' '{}' >"$project/.omarchy-plugin-dev/tasks.json"

OMARCHY_PLUGINS_DIR="$plugins" ./scripts/deploy --dry-run "$project" >/dev/null
[[ ! -e $plugins/dev.deploy-test ]] || {
  printf '[error] dry run created the plugin target\n' >&2
  exit 1
}

OMARCHY_PLUGINS_DIR="$plugins" ./scripts/deploy --apply "$project" >/dev/null
[[ -f $plugins/dev.deploy-test/Service.qml ]]
[[ ! -e $plugins/dev.deploy-test/.omarchy-plugin-dev ]]

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

printf '[ok] deployment helper\n'
