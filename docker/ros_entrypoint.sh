#!/bin/bash
set -e

if [ -f "/opt/ros/humble/setup.bash" ]; then
  source /opt/ros/humble/setup.bash
fi

# Source overlay only when explicitly requested to avoid stale workspace pollution.
if [ "${AUTO_SOURCE_WS:-0}" = "1" ] && [ -f "/workspace/install/setup.bash" ]; then
  source /workspace/install/setup.bash
elif [ "${AUTO_SOURCE_WS:-0}" = "1" ] && [ -f "/root/ros2_ws/install/setup.bash" ]; then
  source /root/ros2_ws/install/setup.bash
fi

exec "$@"
