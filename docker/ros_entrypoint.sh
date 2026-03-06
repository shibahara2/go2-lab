#!/bin/bash
set -e

if [ -f "/opt/ros/humble/setup.bash" ]; then
  source /opt/ros/humble/setup.bash
fi

if [ -f "/workspace/install/setup.bash" ]; then
  source /workspace/install/setup.bash
elif [ -f "/root/ros2_ws/install/setup.bash" ]; then
  source /root/ros2_ws/install/setup.bash
fi

exec "$@"
