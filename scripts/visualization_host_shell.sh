#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "${repo_root}"

if [ -f /opt/ros/humble/setup.bash ]; then
  # shellcheck disable=SC1091
  source /opt/ros/humble/setup.bash
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
