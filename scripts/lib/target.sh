#!/bin/bash

fail() { printf '%s\n' "$*" >&2; exit 1; }
git_read() { timeout -k 2 5 git -c core.hooksPath=/dev/null -c core.fsmonitor=false -C "$target" "$@"; }

valid_manifest() {
  "$JQ" -e --arg id "$id" '.schemaVersion == 1 and .id == $id' "$1/manifest.json" >/dev/null 2>&1
}

identity() {
  if [[ -e $target || -L $target ]]; then stat -c '%d:%i' -- "$target"; else printf absent; fi
}

fingerprint() {
  {
    printf '%s\n' "$target" "$(identity)"
    if [[ -e $target || -L $target ]]; then
      find -P "$target" -printf '%P %y %m %s %T@ %l\0'
    fi
  } | sha256sum | cut -d ' ' -f 1
}

ordinary_checkout() {
  [[ -d $target/.git && ! -L $target/.git ]] || return 1
  [[ $(git_read rev-parse --show-toplevel) == "$(realpath -e -- "$target")" ]] || return 1
  [[ $(realpath -e -- "$(git_read rev-parse --absolute-git-dir)") == "$(realpath -e -- "$target/.git")" ]] || return 1
  [[ $(git_read rev-parse --path-format=absolute --git-common-dir) == "$(realpath -e -- "$target/.git")" ]]
}

existing_directory_kind() {
  if ordinary_checkout 2>/dev/null; then
    printf git-clone
  elif [[ -e $target/.git || -L $target/.git ]]; then
    fail "Refusing to replace a Git checkout with shared or external metadata: $target"
  elif valid_manifest "$target"; then
    printf installed-copy
  else
    fail "Destination is not a recognized installation of $id: $target"
  fi
}

matching_checkout() {
  ordinary_checkout || return 1
  [[ $(git_read config --get remote.origin.url) == "$source" ]] || return 1
  local actual expected branch default_branch
  actual=$(git_read rev-parse HEAD) || return 1
  if [[ -n $ref ]]; then
    if [[ $ref_kind == commit ]]; then expected=$ref
    else expected=$(git_read rev-parse --verify "refs/tags/$ref^{commit}") || return 1; fi
    [[ ${actual,,} == "${expected,,}" ]]
  else
    branch=$(git_read symbolic-ref --short HEAD) || return 1
    default_branch=$(git_read symbolic-ref --short refs/remotes/origin/HEAD) || return 1
    [[ $branch == "${default_branch#origin/}" ]]
  fi
}

protect_sources() {
  local path resolved mounts linked
  [[ $target != / && $target != "$HOME" ]] || fail "Refusing to replace $target"
  mounts=$(findmnt --json --list --output TARGET) || fail 'Cannot check mounted folders before deletion'
  while IFS= read -r path; do
    [[ $path != "$target" && $path != "$target/"* ]] || fail "Unmount $path before replacing this directory"
  done < <("$JQ" -r '.filesystems[].target' <<<"$mounts")
  while IFS= read -r path; do
    resolved=$(realpath -m -- "$path")
    [[ $resolved != "$target" && $resolved != "$target/"* ]] \
      || fail "Move the development source before replacing $target (protected: $resolved)"
  done < <({ printf '%s\n' "$root" "$SCRIPT_DIR/.."; "$JQ" -r '.protected[]' <<<"$request"; })
  if [[ $kind == git-clone && -e $target/.git/worktrees ]]; then
    [[ -d $target/.git/worktrees ]] || fail 'Cannot inspect linked Git worktree metadata'
    linked=$(find "$target/.git/worktrees" -mindepth 1 -maxdepth 1 -print -quit) \
      || fail 'Cannot inspect linked Git worktree metadata'
    [[ -z $linked ]] \
      || fail "Remove or prune linked Git worktrees before replacing their main checkout: $target"
  fi
}

inspect_target() {
  operation=create
  kind=absent
  revision=""
  branch=""
  dirty=false
  if [[ $type == local-source || $type == symlink ]]; then
    [[ -d $source ]] && valid_manifest "$source" || fail "Source is missing or has a different plugin id: $source"
    source=$(realpath -e -- "$source")
  fi
  if [[ $type == local-source ]]; then
    [[ -d $target && $(realpath -e -- "$target") == "$source" ]] \
      || fail 'local-source requires the same existing source and destination'
    operation=reuse
    kind=local-source
  elif [[ -L $target ]]; then
    kind=symlink
    operation=replace
    if [[ $type == symlink && $(realpath -e -- "$target" 2>/dev/null || true) == "$source" ]]; then operation=reuse; fi
  elif [[ -e $target ]]; then
    [[ -d $target ]] || fail "Destination is not a directory: $target"
    kind=$(existing_directory_kind)
    operation=replace
    if [[ $kind == git-clone && $type == git-clone ]] && matching_checkout && valid_manifest "$target"; then
      operation=reuse
    fi
    if [[ $operation == replace ]]; then protect_sources; fi
  fi
  if [[ $type == symlink && $operation != reuse ]]; then
    [[ $source != "$target" && $source != "$target/"* && $target != "$source/"* ]] \
      || fail 'A link cannot overlap its own source'
  fi
  if [[ -d $target && ( $operation == reuse || $kind == git-clone ) ]]; then
    revision=$(git_read rev-parse HEAD 2>/dev/null || true)
    if [[ -n $revision ]]; then
      branch=$(git_read symbolic-ref --short HEAD 2>/dev/null || printf detached)
      local changes
      changes=$(git_read status --porcelain --untracked-files=all) || fail 'Cannot inspect Git changes'
      [[ -z $changes ]] || dirty=true
    fi
  fi
  destructive=false
  if [[ $operation == replace && ( $kind == git-clone || $kind == installed-copy ) ]]; then
    destructive=true
  fi
}

replacement_summary() {
  modified=0 untracked=0 ignored=0 ahead=unknown comparison=unknown
  destructive=false
  if [[ $operation == replace && ( $kind == git-clone || $kind == installed-copy ) ]]; then
    destructive=true
  fi
  [[ $kind == git-clone && $operation == replace ]] || return 0
  local changes line
  changes=$(git_read status --porcelain=v1 --untracked-files=all --ignored) || fail 'Cannot inspect files before deletion'
  while IFS= read -r line; do
    [[ -n $line ]] || continue
    case "${line:0:2}" in
      '??') ((untracked+=1));;
      '!!') ((ignored+=1));;
      *) ((modified+=1));;
    esac
  done <<<"$changes"
  comparison=$(git_read rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)
  if [[ -n $comparison ]]; then
    ahead=$(git_read rev-list --count "$comparison..HEAD") || fail 'Cannot inspect commits before deletion'
  else comparison=unknown; fi
}

report() {
  local digest=""
  if [[ $action != status ]]; then digest=$(fingerprint); fi
  "$JQ" -n --arg operation "$operation" --arg kind "$kind" --arg identity "$(identity)" \
    --arg fingerprint "$digest" --arg revision "$revision" --argjson dirty "$dirty" \
    --arg target "$target" --arg branch "$branch" --argjson modified "$modified" --argjson untracked "$untracked" \
    --argjson ignored "$ignored" --arg ahead "$ahead" --arg comparison "$comparison" \
    --argjson destructive "$destructive" \
    '{operation:$operation,kind:$kind,identity:$identity,fingerprint:$fingerprint,
      revision:$revision,branch:$branch,dirty:$dirty,target:$target,modified:$modified,
      untracked:$untracked,ignored:$ignored,ahead:$ahead,comparison:$comparison,
      destructive:$destructive}'
}
