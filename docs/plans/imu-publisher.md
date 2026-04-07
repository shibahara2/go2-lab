# IMU Publisher Plan

## Summary

- Add a new ROS 2 package under `src/ros/imu_publisher`.
- Subscribe to Go2 `unitree_go::msg::LowState` on `/lowstate`.
- Publish `sensor_msgs/msg/Imu` on `/go2/imu` with `frame_id` set to `imu_link`.
- Keep the implementation inside `go2-lab`; avoid unnecessary edits outside the new package.

## Implementation

- Create package `imu_publisher` with `ament_cmake`.
- Add one executable node named `imu_publisher`.
- Map fields as follows:
  - `imu_state.quaternion[0..3]` -> `orientation.w/x/y/z`
  - `imu_state.gyroscope[0..2]` -> `angular_velocity.x/y/z`
  - `imu_state.accelerometer[0..2]` -> `linear_acceleration.x/y/z`
  - `header.stamp` -> `now()`
  - `header.frame_id` -> `imu_link`
- Leave topic names fixed in v1:
  - input `/lowstate`
  - output `/go2/imu`

## Validation

- Build with `make colcon-build`.
- Run with `ros2 run imu_publisher imu_publisher`.
- Verify one message with `ros2 topic echo /go2/imu --once`.
- Confirm existing packages still build.

## Follow-ups

- Add parameters for input topic, output topic, or frame ID if needed later.
- Add covariance values when the source characteristics are clarified.
- Add a launch file only if this node becomes part of a standard bring-up flow.
