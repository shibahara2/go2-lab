#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "${repo_root}"

env_file="${repo_root}/.env"
if [[ -f "${env_file}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${env_file}"
  set +a
fi

if [[ "${DISTRIBUTED_MODE:-0}" != "1" ]]; then
  echo "zenoh client is disabled because DISTRIBUTED_MODE=${DISTRIBUTED_MODE:-0}." >&2
  echo "Default mode uses workstation host + optional Jetson container." >&2
  echo "Set DISTRIBUTED_MODE=1 in .env to enable distributed mode." >&2
  exit 1
fi

config_path="${repo_root}/configs/zenoh/zenoh-config-client.json"
binary_path="${repo_root}/src/zenoh/target/release/zenohd"

if [[ ! -x "${binary_path}" ]]; then
  echo "Missing zenohd binary: ${binary_path}" >&2
  echo "Run 'make zenoh-build' first." >&2
  exit 1
fi

if [[ ! -f "${config_path}" ]]; then
  echo "Missing zenoh client config: ${config_path}" >&2
  echo "Run 'make sync-configs' first." >&2
  exit 1
fi

if [[ -n "${ZENOH_CONFIG_OVERRIDE:-}" ]]; then
  echo "[auto-env] exported: ZENOH_CONFIG_OVERRIDE=${ZENOH_CONFIG_OVERRIDE}"
else
  echo "[auto-env] ZENOH_CONFIG_OVERRIDE is empty"
fi

exec "${binary_path}" -c "${config_path}" "$@"
