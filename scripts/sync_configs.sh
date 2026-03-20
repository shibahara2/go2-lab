#!/usr/bin/env bash
set -euo pipefail

target="${1:?Usage: $0 <TARGET> (jetson|bridge|visualization-host)}"

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

# Load target env
target_env="${repo_root}/.env.${target}"
if [[ ! -f "${target_env}" ]]; then
  echo "Error: .env.${target} not found." >&2
  echo "Run: cp .env.${target}.example .env.${target}" >&2
  exit 1
fi
# shellcheck disable=SC1090
set -a
source "${target_env}"
set +a

render_file() {
  local src_rel="$1"
  local dest_rel="$2"
  local vars="$3"
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

  envsubst "${vars}" < "${src}" > "${dest}"
  echo "Rendered ${src_rel} -> ${dest_rel}"
}

render_file "configs/livox/MID360_config.json" \
  "src/ros/livox_ros_driver2/config/MID360_config.json" \
  '${LIDAR_HOST_IP} ${LIDAR_DEVICE_IP}'

render_file "configs/unitree_ros2/setup.sh" \
  "src/ros/unitree_ros2/setup.sh" \
  '${NETWORK_INTERFACE} ${RMW_IMPLEMENTATION}'

render_file "configs/zenoh/zenoh-config-client.json.tmpl" \
  "configs/zenoh/zenoh-config-client.json" \
  '${ZENOH_ROUTER_IP} ${ZENOH_ROUTER_PORT}'

render_file "configs/zenoh/zenoh-config-router.json.tmpl" \
  "configs/zenoh/zenoh-config-router.json" \
  '${ZENOH_ROUTER_PORT}'
