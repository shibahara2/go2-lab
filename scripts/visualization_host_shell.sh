#!/usr/bin/env zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "${repo_root}"

# Load .env if available
if [ -f "${repo_root}/.env" ]; then
  set -a
  source "${repo_root}/.env"
  set +a
fi

if [ -f /opt/ros/humble/setup.zsh ]; then
  set +u
  source /opt/ros/humble/setup.zsh
  set -u
  echo "[auto-source] sourced: /opt/ros/humble/setup.zsh"
else
  echo "[auto-source] missing: /opt/ros/humble/setup.zsh"
fi

export RMW_IMPLEMENTATION="${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp}"
export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}"
echo "[auto-env] exported: RMW_IMPLEMENTATION=${RMW_IMPLEMENTATION}"
echo "[auto-env] exported: ROS_DOMAIN_ID=${ROS_DOMAIN_ID}"

if [ "$#" -gt 0 ]; then
  exec "$@"
fi

exec zsh -i
