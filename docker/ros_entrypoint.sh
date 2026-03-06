#!/bin/bash
set -e

if [ -f "/opt/ros/humble/setup.bash" ]; then
  source /opt/ros/humble/setup.bash
fi

if [ -f "/root/ros2_ws/install/setup.bash" ]; then
  source /root/ros2_ws/install/setup.bash
fi

exec "$@"
