#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

record_patch() {
  local patch_rel="$1"
  local target_rel="$2"
  local patch_path="${repo_root}/${patch_rel}"
  local target_path="${repo_root}/${target_rel}"
  local patch_dir
  local tmpfile

  if [[ ! -d "${target_path}" ]]; then
    echo "Patch target not found: ${target_rel}" >&2
    exit 1
  fi

  patch_dir="$(dirname "${patch_path}")"
  mkdir -p "${patch_dir}"

  tmpfile="$(mktemp)"
  trap 'rm -f "${tmpfile}"' EXIT

  git -C "${target_path}" diff -- . > "${tmpfile}"

  if [[ ! -s "${tmpfile}" ]]; then
    rm -f "${patch_path}"
    echo "No local changes in ${target_rel}; removed ${patch_rel}."
    return 0
  fi

  mv "${tmpfile}" "${patch_path}"
  trap - EXIT
  echo "Recorded ${target_rel} -> ${patch_rel}"
}

record_patch "patches/fast_lio/0001-local-changes.patch" "src/ros/FAST_LIO"
