#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <jetson|desktop>" >&2
  exit 1
fi

target="$1"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
common_file="${repo_root}/configs/deploy/src-common.txt"
target_file="${repo_root}/configs/deploy/src-${target}.txt"

if [[ ! -f "${common_file}" ]]; then
  echo "Config not found: ${common_file}" >&2
  exit 1
fi

if [[ ! -f "${target_file}" ]]; then
  echo "Config not found: ${target_file}" >&2
  exit 1
fi

parse_file() {
  local file="$1"
  while IFS= read -r line || [[ -n "${line}" ]]; do
    trimmed="$(echo "${line}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "${trimmed}" ]] && continue
    [[ "${trimmed}" =~ ^# ]] && continue
    path="${repo_root}/${trimmed}"
    if [[ ! -e "${path}" ]]; then
      echo "Configured path not found: ${trimmed} (from ${file})" >&2
      exit 1
    fi
    printf '%s\n' "${trimmed}"
  done < "${file}"
}

{
  parse_file "${common_file}"
  parse_file "${target_file}"
} | awk '!seen[$0]++'
