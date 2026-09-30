#!/bin/bash
set -euo pipefail

plugin_root=$(pwd -P)
test_root=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/omarchy-plugin-dev-wrapper-test.XXXXXX")
cleanup() {
  rm -rf -- "$test_root"
}
trap cleanup EXIT

project="$test_root/project"
mkdir -p "$project/ignored"
printf '%s\n' '{}' >"$project/manifest.json"
printf '%s\n' 'ignored/' >"$project/.gitignore"
ln -s -- ../manifest.json "$project/ignored/manifest.json"

mock_omarchy="$test_root/omarchy"
printf '%s\n' \
  '#!/bin/bash' \
  'set -euo pipefail' \
  'stage=$3' \
  '[[ -f $stage/manifest.json ]]' \
  '[[ ! -e $stage/ignored/manifest.json ]]' \
  'printf '\''validated\n'\''' >"$mock_omarchy"
chmod +x "$mock_omarchy"
(
  cd "$project"
  OMARCHY_PLUGIN_DEV_OMARCHY="$mock_omarchy" \
    "$plugin_root/scripts/validate-manifest"
) >"$test_root/validate.out"
rg -Fq 'Validating plugin manifest' "$test_root/validate.out"
rg -Fq 'Project directory:' "$test_root/validate.out"
rg -Fq 'Staging directory:' "$test_root/validate.out"
rg -Fq '$ stage tracked and non-ignored project files' "$test_root/validate.out"
rg -Fq '$ omarchy plugin validate <staging>' "$test_root/validate.out"
rg -Fq 'validated' "$test_root/validate.out"
rg -Fq 'Plugin manifest is valid' "$test_root/validate.out"

mock_qmllint="$test_root/qmllint"
printf '%s\n' \
  '#!/bin/bash' \
  'printf '\''Warning: /tmp/Test.qml:2:3: example warning [test]\n'\''' >"$mock_qmllint"
chmod +x "$mock_qmllint"
(
  cd "$project"
  OMARCHY_PLUGIN_DEV_QMLLINT="$mock_qmllint" \
    OMARCHY_PLUGIN_DEV_QML_FILE_COUNT=2 \
    "$plugin_root/scripts/lint-qml" -I /tmp/import /tmp/Test.qml
) >"$test_root/lint.out"
rg -Fq 'Linting plugin QML' "$test_root/lint.out"
rg -Fq 'Source files: 2' "$test_root/lint.out"
rg -Fq '$ qmllint -I <import-paths> <qml-files>' "$test_root/lint.out"
rg -Fq 'example warning' "$test_root/lint.out"
rg -Fq 'QML lint completed without errors' "$test_root/lint.out"

printf '%s\n' '#!/bin/bash' 'exit 9' >"$mock_qmllint"
if (
  cd "$project"
  OMARCHY_PLUGIN_DEV_QMLLINT="$mock_qmllint" \
    "$plugin_root/scripts/lint-qml" /tmp/Test.qml
) >"$test_root/lint-failure.out" 2>"$test_root/lint-failure.err"; then
  printf '[error] lint wrapper accepted a failed qmllint run\n' >&2
  exit 1
fi
rg -Fq '[ERROR]' "$test_root/lint-failure.err"
rg -Fq 'QML lint failed' "$test_root/lint-failure.err"

mock_journalctl="$test_root/journalctl"
printf '%s\n' '#!/bin/bash' 'printf '\''journal output\n'\''' >"$mock_journalctl"
chmod +x "$mock_journalctl"
(
  cd "$project"
  OMARCHY_PLUGIN_DEV_JOURNALCTL="$mock_journalctl" \
    "$plugin_root/scripts/shell-logs" _COMM=quickshell --follow
) >"$test_root/logs.out"
rg -Fq 'Following Omarchy shell logs' "$test_root/logs.out"
rg -Fq 'Journal match: _COMM=quickshell' "$test_root/logs.out"
rg -Fq '$ journalctl --user -b <match> -f' "$test_root/logs.out"
rg -Fq 'journal output' "$test_root/logs.out"
if rg -Fq '[OK]' "$test_root/logs.out"; then
  printf '[error] streaming logs reported a completion status\n' >&2
  exit 1
fi

for state in detected absent; do
  "$plugin_root/scripts/skip-project-test" "$state" >"$test_root/skip-$state.out"
  rg -Fq '[WARN]' "$test_root/skip-$state.out"
  rg -Fq ':OmaDevInit' "$test_root/skip-$state.out"
  if rg -Fq '[OK]' "$test_root/skip-$state.out"; then
    printf '[error] skipped tests reported a passing test\n' >&2
    exit 1
  fi
done
rg -Fq 'Tests detected but not configured; skipping' "$test_root/skip-detected.out"
rg -Fq 'Run :OmaDevInit to configure a test runner' "$test_root/skip-detected.out"
rg -Fq 'Tests NOT detected; skipping' "$test_root/skip-absent.out"
rg -Fq 'Add tests and configure them with :OmaDevInit' "$test_root/skip-absent.out"
if "$plugin_root/scripts/skip-project-test" unknown >"$test_root/skip-invalid.out" 2>&1; then
  printf '[error] skipped-test helper accepted an unknown state\n' >&2
  exit 1
fi

status=0
"$plugin_root/scripts/run-project-test" /bin/sh -c 'exit 7' \
  >"$test_root/test-failure.out" 2>&1 || status=$?
[[ $status == 7 ]]
rg -Fq '[ERROR]' "$test_root/test-failure.out"
rg -Fq 'Project test failed' "$test_root/test-failure.out"

printf '[ok] task wrappers\n'
