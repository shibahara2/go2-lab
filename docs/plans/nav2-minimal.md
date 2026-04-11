# Nav2 Minimal Integration Plan

## Summary

- Introduce a minimal `nav2` stack for 2D autonomous navigation in `go2-lab`.
- Reuse the existing localization and motion-control building blocks already present in this repository:
  - FAST_LIO for odometry publishing.
  - `cmd_vel_control` for `/cmd_vel` to Unitree sport request conversion.
  - `imu_publisher` for Go2 IMU publication when needed.
- Keep the first milestone focused on a working indoor demo on mostly flat ground.
- Avoid larger changes such as custom planners, multi-floor mapping, or foothold-aware locomotion in v1.

## Current Repository Baseline

- ROS 2 Humble is the current target environment.
- The existing bring-up already launches Livox and FAST_LIO and verifies `/Odometry` in RViz.
- The repository already contains a node that subscribes to `/cmd_vel` and forwards motion requests to Go2.
- `nav2` packages are not included in the current dependency list.
- The current RViz guidance uses `camera_init` as the fixed frame, which is not sufficient as-is for a standard `nav2` setup.

## Minimal Target Architecture

- Sensors and state:
  - MID360 point cloud from `livox_ros_driver2`
  - Go2 IMU from `imu_publisher`
  - Odometry from FAST_LIO
- Navigation stack:
  - `map_server`
  - `amcl`
  - `planner_server`
  - `controller_server`
  - `behavior_server`
  - `bt_navigator`
  - `waypoint_follower`
  - `lifecycle_manager`
- Control output:
  - `nav2` publishes `/cmd_vel`
  - existing `cmd_vel_control` forwards `/cmd_vel` to `/api/sport/request`

## Required Interface Contract

`nav2` should be introduced only after the following contract is satisfied.

### Frames

- `map`
- `odom`
- `base_link`
- sensor frames such as `imu_link` and the LiDAR frame

### TF expectations

- `map -> odom`
  - published by `amcl`
- `odom -> base_link`
  - must be available continuously from the localization or odometry layer
- `base_link -> <sensor_frame>`
  - static transforms from URDF or static transform publishers

### Topics

- Required inputs for v1:
  - `/scan` or a costmap-compatible substitute
  - `/tf`
  - `/tf_static`
  - localization input compatible with `amcl`
- Existing outputs available now:
  - `/Odometry` from FAST_LIO
  - `/cmd_vel` consumer in `cmd_vel_control`
  - `/go2/imu` from `imu_publisher`

## Main Gap To Close First

The largest integration gap is not the `nav2` package install itself. It is the mismatch between the repository's current localization output and what a minimal `nav2` deployment expects.

- FAST_LIO currently provides odometry in a LiDAR-centric workflow and RViz is configured around `camera_init`.
- A standard `nav2` setup expects a clear `map -> odom -> base_link` frame chain.
- `nav2` local and global costmaps usually expect a 2D obstacle source, most commonly `LaserScan`.
- MID360 data is currently handled as point clouds, so an adapter layer is needed unless point-cloud costmaps are configured directly.

## Recommended Minimal v1 Scope

Choose the simplest path that can produce a reliable demo:

1. Treat the robot as a planar base for navigation purposes.
2. Use existing `cmd_vel_control` as the only motion interface.
3. Use a prebuilt 2D occupancy map for the first milestone.
4. Use `amcl` for `map -> odom`.
5. Derive or provide a 2D obstacle source for costmaps.
6. Keep speed limits conservative and disable aggressive recovery behavior until the base behavior is characterized.

## Concrete Repository Changes

### 1. Add ROS package dependencies

Add the following packages to `configs/deps/packages.txt`:

- `ros-humble-navigation2`
- `ros-humble-nav2-bringup`
- `ros-humble-nav2-map-server`
- `ros-humble-nav2-amcl`
- `ros-humble-nav2-lifecycle-manager`
- `ros-humble-nav2-controller`
- `ros-humble-nav2-planner`
- `ros-humble-nav2-behavior-tree`
- `ros-humble-nav2-bt-navigator`
- `ros-humble-nav2-waypoint-follower`
- `ros-humble-nav2-costmap-2d`
- `ros-humble-tf2-ros`
- `ros-humble-tf2-tools`

Minimal install note:

- If package count should stay small, `ros-humble-navigation2` and `ros-humble-nav2-bringup` are usually enough as a first pass on Humble.

### 2. Add a bring-up package for local integration

Create a new package under `src/ros/nav2_bringup_go2` containing:

- `launch/nav2_minimal.launch.py`
- `config/nav2_params.yaml`
- `config/map.yaml`
- `rviz/nav2.rviz`

This package should own repository-specific integration only. Do not edit upstream `nav2` packages.

### 3. Normalize the frame tree

Add one of the following:

- preferred:
  - a simple URDF and `robot_state_publisher` for `base_link`, `imu_link`, and LiDAR frames
- fallback:
  - explicit static transform publishers in the launch file

For v1, document and enforce:

- `base_link` as the robot navigation base frame
- `odom` as the local odometry frame consumed by `nav2`
- `map` as the global frame

### 4. Bridge odometry into the expected frame convention

If FAST_LIO does not already publish `odom -> base_link` in the form needed by `nav2`, add a small adapter node:

- subscribe to `/Odometry`
- republish as `nav_msgs/msg/Odometry` on `/odom`
- publish matching TF `odom -> base_link`
- optionally remap frame IDs from `camera_init` or sensor-centric frames into the navigation convention

This adapter is likely the smallest and safest repo-local code addition.

### 5. Provide a costmap-compatible obstacle source

Pick one of these v1 options:

- recommended:
  - generate `/scan` from the LiDAR point cloud using a pointcloud-to-laserscan node
- alternative:
  - configure local costmap directly from point clouds if the data rate and tuning are acceptable

The first option is simpler to debug and aligns with a standard `amcl` setup.

### 6. Add nav2 parameterization for Go2

`config/nav2_params.yaml` should initially keep:

- low max linear velocity
- low max angular velocity
- conservative acceleration limits
- small controller frequency increase only after basic validation
- recovery behaviors either limited or disabled initially
- local and global costmap dimensions sized for indoor testing

### 7. Add a simple launch flow

`launch/nav2_minimal.launch.py` should start:

- static transforms or `robot_state_publisher`
- odometry adapter if needed
- pointcloud-to-laserscan if used
- map server
- AMCL
- Nav2 servers
- lifecycle manager
- existing `cmd_vel_control`

Keep Livox, FAST_LIO, and `imu_publisher` outside this launch in the first iteration if that makes failures easier to isolate.

## Suggested Implementation Order

1. Install `nav2` dependencies.
2. Verify the existing stack still builds.
3. Define the navigation frame convention.
4. Implement the odometry adapter to publish `/odom` and `odom -> base_link`.
5. Add static sensor transforms or `robot_state_publisher`.
6. Add pointcloud-to-laserscan if needed.
7. Create the bring-up package and launch file.
8. Add a static map and basic `amcl` config.
9. Tune controller and costmap conservatively.
10. Validate first with teleop disabled and wide-open space.

## Validation Checklist

Before attempting goal-based navigation, confirm:

- `ros2 topic echo /odom --once` succeeds
- `ros2 topic echo /cmd_vel --once` shows messages when a goal is active
- `ros2 topic echo /go2/imu --once` succeeds if IMU is part of the configuration
- `ros2 run tf2_tools view_frames` shows `map -> odom -> base_link`
- RViz can use `map` as the fixed frame
- local costmap receives obstacles
- sending a short goal produces low-speed motion without oscillation

## Explicit Non-Goals For v1

- Full 3D navigation
- Rough-terrain foothold planning
- Outdoor large-scale mapping
- Dynamic gait selection from the navigation stack
- Multi-robot coordination

## Risks

- FAST_LIO frame semantics may not directly match `nav2` assumptions.
- Four-legged locomotion may not track `cmd_vel` like a wheeled base, especially at low speed or high yaw rate.
- A 3D LiDAR reduced to 2D scans can create blind spots or unstable obstacles unless carefully tuned.
- AMCL performance depends on the quality of the 2D map and scan model.

## Recommended First Deliverable

The first concrete milestone should be:

- launch Livox and FAST_LIO
- publish `/go2/imu`
- adapt `/Odometry` into `/odom` plus TF
- convert point cloud to `/scan`
- start `nav2`
- send a short indoor goal on a prebuilt map
- observe `/cmd_vel` and controlled Go2 motion

This is the smallest milestone that proves the architecture without overcommitting to a larger refactor.
