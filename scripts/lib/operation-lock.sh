#!/bin/bash

omadev_lock_directory() {
  local id=$1
  [[ $id =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && $id != *..* ]] || {
    printf 'Invalid plugin id\n' >&2; return 1;
  }
  omadev_lock_dir="${XDG_RUNTIME_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}}/omarchy-plugin-dev"
  [[ ! -L $omadev_lock_dir ]] || { printf 'Lock directory is a symlink\n' >&2; return 1; }
  mkdir -p -- "$omadev_lock_dir" || return
  [[ ! -L $omadev_lock_dir/$id.lock && ! -L $omadev_lock_dir/$id.workers ]] || {
    printf 'Lock file is a symlink\n' >&2; return 1;
  }
}

omadev_worker_lock() {
  omadev_lock_directory "$1" || return
  exec {omadev_worker_fd}>>"$omadev_lock_dir/$1.workers"
  flock -sn "$omadev_worker_fd"
}

omadev_lock() {
  omadev_lock_directory "$1" || return
  exec {omadev_lock_fd}>>"$omadev_lock_dir/$1.lock"
  exec {omadev_worker_fd}>>"$omadev_lock_dir/$1.workers"
  if ! flock -n "$omadev_lock_fd" || ! flock -n "$omadev_worker_fd"; then
    printf 'Another build or source selection is running for %s\n' "$1" >&2
    return 1
  fi
}
