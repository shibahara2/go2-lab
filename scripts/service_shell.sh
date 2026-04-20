#!/usr/bin/env zsh
set -euo pipefail

container_name="${1:?Usage: $0 <container_name> <ros_setup> <source_unitree yes|no>}"
ros_setup="${2:?Usage: $0 <container_name> <ros_setup> <source_unitree yes|no>}"
source_unitree="${3:-yes}"

docker exec -it "${container_name}" zsh -c "
  cd /workspace

  if [ -f '${ros_setup}' ]; then
    set +u
    source '${ros_setup}'
    set -u
    echo '[auto-source] sourced: ${ros_setup}'
  else
    echo '[auto-source] missing: ${ros_setup}'
  fi

  if [ '${source_unitree}' = 'yes' ] && [ -f /workspace/src/ros/unitree_ros2/setup.sh ]; then
    set +u
    source /workspace/src/ros/unitree_ros2/setup.sh
    set -u
    echo '[auto-source] sourced: /workspace/src/ros/unitree_ros2/setup.sh'
  else
    echo '[auto-source] skipped: /workspace/src/ros/unitree_ros2/setup.sh'
  fi

  if [ -f /workspace/install/setup.zsh ]; then
    set +u
    source /workspace/install/setup.zsh
    set -u
    echo '[auto-source] sourced: /workspace/install/setup.zsh'
  else
    echo '[auto-source] missing: /workspace/install/setup.zsh'
  fi

  export LD_LIBRARY_PATH=/usr/local/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}
  export RMW_IMPLEMENTATION=\"\${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp}\"
  export ROS_DOMAIN_ID=\"\${ROS_DOMAIN_ID:-0}\"
  echo \"[auto-env] exported: RMW_IMPLEMENTATION=\${RMW_IMPLEMENTATION}\"
  echo \"[auto-env] exported: ROS_DOMAIN_ID=\${ROS_DOMAIN_ID}\"

  exec zsh -i
"
