#!/bin/bash
echo "Setup unitree ros2 environment"
if [ -f /opt/ros/jazzy/setup.zsh ]; then
  source /opt/ros/jazzy/setup.zsh
else
  source /opt/ros/humble/setup.zsh
fi
# source $HOME/unitree_ros2/cyclonedds_ws/install/setup.bash
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp

# CycloneDDS will later fail with "does not match an available interface"
# if this interface name is wrong for the current host.
if command -v ip >/dev/null 2>&1; then
  if ! ip link show "wlP9s9" >/dev/null 2>&1; then
    echo "[setup.sh] Warning: NETWORK_INTERFACE=wlP9s9 was not found on this host." >&2
    echo "[setup.sh] Check '.env' and re-run 'make sync-configs'." >&2
  fi
fi

export CYCLONEDDS_URI='<CycloneDDS><Domain><General><Interfaces>
                            <NetworkInterface name="wlP9s9" priority="default" multicast="default" />
                        </Interfaces></General></Domain></CycloneDDS>'
