#!/usr/bin/env zsh
set -euo pipefail

project_dir="${1:?Usage: $0 <project_dir>}"

docker exec -it dgx-spark zsh -c '
  cd /workspace

  if [ -f /opt/ros/jazzy/setup.zsh ]; then
    set +u
    source /opt/ros/jazzy/setup.zsh
    set -u
    echo "[auto-source] sourced: /opt/ros/jazzy/setup.zsh"
  else
    echo "[auto-source] missing: /opt/ros/jazzy/setup.zsh"
  fi

  if [ -f /workspace/src/ros/unitree_ros2/setup.sh ]; then
    set +u
    source /workspace/src/ros/unitree_ros2/setup.sh
    set -u
    echo "[auto-source] sourced: /workspace/src/ros/unitree_ros2/setup.sh"
  else
    echo "[auto-source] missing: /workspace/src/ros/unitree_ros2/setup.sh"
  fi

  if [ -f /workspace/install/setup.zsh ]; then
    set +u
    source /workspace/install/setup.zsh
    set -u
    echo "[auto-source] sourced: /workspace/install/setup.zsh"
  else
    echo "[auto-source] missing: /workspace/install/setup.zsh"
  fi

  export RMW_IMPLEMENTATION="${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp}"
  export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}"
  echo "[auto-env] exported: RMW_IMPLEMENTATION=${RMW_IMPLEMENTATION}"
  echo "[auto-env] exported: ROS_DOMAIN_ID=${ROS_DOMAIN_ID}"

  exec zsh -i
'
