#!/bin/bash
echo "Setup unitree ros2 environment"
source /opt/ros/humble/setup.zsh
# source $HOME/unitree_ros2/cyclonedds_ws/install/setup.bash
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp

network_interfaces_raw="CHANGE_ME"
network_interfaces_xml=""

# CycloneDDS will later fail with "does not match an available interface"
# if any configured interface name is wrong for the current host.
old_ifs="${IFS}"
IFS=','
for iface in ${network_interfaces_raw}; do
  IFS="${old_ifs}"
  iface="${iface#"${iface%%[![:space:]]*}"}"
  iface="${iface%"${iface##*[![:space:]]}"}"

  if [ -z "${iface}" ]; then
    IFS=','
    continue
  fi

  if command -v ip >/dev/null 2>&1; then
    if ! ip link show "${iface}" >/dev/null 2>&1; then
      echo "[setup.sh] Warning: NETWORK_INTERFACE entry '${iface}' was not found on this host." >&2
      echo "[setup.sh] Check '.env' and re-run 'make sync-configs TARGET=<target>'." >&2
    fi
  fi

  network_interfaces_xml="${network_interfaces_xml}
                            <NetworkInterface name=\"${iface}\" priority=\"default\" multicast=\"default\" />"
  IFS=','
done
IFS="${old_ifs}"

if [ -z "${network_interfaces_xml}" ]; then
  echo "[setup.sh] Warning: NETWORK_INTERFACE is empty after parsing: ${network_interfaces_raw}" >&2
  echo "[setup.sh] Check '.env' and re-run 'make sync-configs TARGET=<target>'." >&2
fi

export CYCLONEDDS_URI="$(cat <<EOF
<CycloneDDS><Domain><General><Interfaces>${network_interfaces_xml}
                        </Interfaces></General></Domain></CycloneDDS>
EOF
)"
