#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

apply_patch_dir() {
  local patch_dir="$1"
  local target_dir="$2"

  if [[ ! -d "${repo_root}/${patch_dir}" ]]; then
    return 0
  fi

  if [[ ! -d "${repo_root}/${target_dir}" ]]; then
    echo "Patch target not found: ${target_dir}" >&2
    exit 1
  fi

  while IFS= read -r patch_file; do
    echo "Applying ${patch_dir}/$(basename "${patch_file}") -> ${target_dir}"
    git -C "${repo_root}/${target_dir}" apply "${patch_file}"
  done < <(find "${repo_root}/${patch_dir}" -type f -name '*.patch' | sort)
}

apply_patch_dir "patches/fast_lio" "src/ros/FAST_LIO"
