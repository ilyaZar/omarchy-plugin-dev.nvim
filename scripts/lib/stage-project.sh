#!/bin/bash

omarchy_plugin_dev_stage_project() {
  local root=$1
  local stage=$2
  local rsync_command=$3
  local excludes=(
    --exclude=.git/
    --exclude=.omarchy-plugin-dev/
    --exclude=.sublime/
    --exclude=.luacov
    --exclude=coverage/
  )

  if command -v git >/dev/null 2>&1 \
    && git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    (
      cd -- "$root"
      git ls-files --cached --others --exclude-standard -z -- . \
        | "$rsync_command" -aR --from0 --files-from=- \
          --ignore-missing-args -- ./ "$stage/"
    )
    return
  fi

  "$rsync_command" -a "${excludes[@]}" \
    --filter='dir-merge,- .gitignore' -- "$root/" "$stage/"
}
