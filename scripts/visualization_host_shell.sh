#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "${repo_root}"

# Load .env.visualization-host if available
if [ -f "${repo_root}/.env.visualization-host" ]; then
  set -a
  # shellcheck disable=SC1090
  source "${repo_root}/.env.visualization-host"
  set +a
fi

if [ -f /opt/ros/humble/setup.bash ]; then
  # shellcheck disable=SC1091
  set +u
  source /opt/ros/humble/setup.bash
  set -u
  echo "[auto-source] sourced: /opt/ros/humble/setup.bash"
else
  echo "[auto-source] missing: /opt/ros/humble/setup.bash"
fi

export RMW_IMPLEMENTATION="${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp}"
export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}"
echo "[auto-env] exported: RMW_IMPLEMENTATION=${RMW_IMPLEMENTATION}"
echo "[auto-env] exported: ROS_DOMAIN_ID=${ROS_DOMAIN_ID}"

if [ "$#" -gt 0 ]; then
  exec "$@"
fi

exec bash -i
