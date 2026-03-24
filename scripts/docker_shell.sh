#!/usr/bin/env zsh
set -euo pipefail

project_dir="${1:?Usage: $0 <project_dir> <target>}"
target="${2:?Usage: $0 <project_dir> <target>}"

docker compose \
  --project-directory "${project_dir}/docker" \
  -f "${project_dir}/docker/docker-compose.yml" \
  --env-file "${project_dir}/.env" \
  exec -w / "${target}" zsh -c '
    cd /workspace

    if [ -f /workspace/src/ros/unitree_ros2/setup.sh ]; then
      source /workspace/src/ros/unitree_ros2/setup.sh
      echo "[auto-source] sourced: /workspace/src/ros/unitree_ros2/setup.sh"
    else
      echo "[auto-source] missing: /workspace/src/ros/unitree_ros2/setup.sh"
    fi

    if [ -f /workspace/install/setup.zsh ]; then
      source /workspace/install/setup.zsh
      echo "[auto-source] sourced: /workspace/install/setup.zsh"
    else
      echo "[auto-source] missing: /workspace/install/setup.zsh"
    fi

    exec zsh -i
  '
