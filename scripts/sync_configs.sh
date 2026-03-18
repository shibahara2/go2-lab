#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

copy_file() {
  local src_rel="$1"
  local dest_rel="$2"
  local src="${repo_root}/${src_rel}"
  local dest="${repo_root}/${dest_rel}"
  local dest_dir

  if [[ ! -f "${src}" ]]; then
    echo "Config source not found: ${src_rel}" >&2
    exit 1
  fi

  dest_dir="$(dirname "${dest}")"
  if [[ ! -d "${dest_dir}" ]]; then
    echo "Config destination directory not found: ${dest_rel}" >&2
    exit 1
  fi

  cp "${src}" "${dest}"
  echo "Synced ${src_rel} -> ${dest_rel}"
}

copy_file "configs/livox/MID360_config.json" "src/ros/livox_ros_driver2/config/MID360_config.json"
copy_file "configs/unitree_ros2/setup.sh" "src/ros/unitree_ros2/setup.sh"
