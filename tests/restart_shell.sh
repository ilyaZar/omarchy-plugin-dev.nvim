#!/bin/bash
set -euo pipefail

test_root=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/omarchy-plugin-dev-restart-test.XXXXXX")
cleanup() {
  rm -rf -- "$test_root"
}
trap cleanup EXIT

mock_omarchy="$test_root/omarchy"
args_log="$test_root/args.log"
printf '%s\n' \
  '#!/bin/bash' \
  'set -euo pipefail' \
  'printf '\''%s\n'\'' "$*" >"$ARGS_LOG"' \
  'exit "${MOCK_EXIT_CODE:-0}"' >"$mock_omarchy"
chmod +x "$mock_omarchy"

ARGS_LOG="$args_log" OMARCHY_PLUGIN_DEV_OMARCHY="$mock_omarchy" \
  ./scripts/restart-shell >"$test_root/success.out"
[[ $(<"$args_log") == "restart shell" ]]
rg -Fq 'Restarting Omarchy shell' "$test_root/success.out"
rg -Fq '$ omarchy restart shell' "$test_root/success.out"
rg -Fq 'Omarchy shell restarted and ready' "$test_root/success.out"

if ARGS_LOG="$args_log" MOCK_EXIT_CODE=1 OMARCHY_PLUGIN_DEV_OMARCHY="$mock_omarchy" \
  ./scripts/restart-shell >"$test_root/failure.out" 2>"$test_root/failure.err"; then
  printf '[error] restart helper accepted a failed Omarchy restart\n' >&2
  exit 1
fi
if rg -Fq 'restarted and ready' "$test_root/failure.out"; then
  printf '[error] restart helper reported success after a failed restart\n' >&2
  exit 1
fi
rg -Fq '[ERROR]' "$test_root/failure.err"
rg -Fq 'Omarchy shell restart failed' "$test_root/failure.err"

printf '[ok] shell restart helper\n'
