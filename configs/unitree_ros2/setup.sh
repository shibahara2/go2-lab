#!/bin/bash
echo "Setup unitree ros2 environment"
source /opt/ros/humble/setup.bash
# source $HOME/unitree_ros2/cyclonedds_ws/install/setup.bash
export RMW_IMPLEMENTATION=${RMW_IMPLEMENTATION}
export CYCLONEDDS_URI='<CycloneDDS><Domain><General><Interfaces>
                            <NetworkInterface name="${NETWORK_INTERFACE}" priority="default" multicast="default" />
                        </Interfaces></General></Domain></CycloneDDS>'
