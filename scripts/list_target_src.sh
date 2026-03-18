#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <target>" >&2
  exit 1
fi

target="$1"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
target_file="${repo_root}/configs/deploy/src-${target}.txt"

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

parse_file "${target_file}"
