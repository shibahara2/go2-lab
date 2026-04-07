#include <array>
#include <memory>

#include "rclcpp/rclcpp.hpp"
#include "sensor_msgs/msg/imu.hpp"
#include "unitree_go/msg/low_state.hpp"

namespace
{
constexpr char kInputTopic[] = "/lowstate";
constexpr char kOutputTopic[] = "/go2/imu";
constexpr char kFrameId[] = "imu_link";
}  // namespace

class ImuPublisherNode : public rclcpp::Node
{
public:
  ImuPublisherNode() : Node("imu_publisher")
  {
    imu_publisher_ = create_publisher<sensor_msgs::msg::Imu>(kOutputTopic, 10);
    low_state_subscription_ = create_subscription<unitree_go::msg::LowState>(
        kInputTopic, 10,
        std::bind(&ImuPublisherNode::handle_low_state, this, std::placeholders::_1));
  }

private:
  void handle_low_state(const unitree_go::msg::LowState::SharedPtr message)
  {
    sensor_msgs::msg::Imu imu_message;
    imu_message.header.stamp = get_clock()->now();
    imu_message.header.frame_id = kFrameId;

    imu_message.orientation.w = message->imu_state.quaternion[0];
    imu_message.orientation.x = message->imu_state.quaternion[1];
    imu_message.orientation.y = message->imu_state.quaternion[2];
    imu_message.orientation.z = message->imu_state.quaternion[3];

    imu_message.angular_velocity.x = message->imu_state.gyroscope[0];
    imu_message.angular_velocity.y = message->imu_state.gyroscope[1];
    imu_message.angular_velocity.z = message->imu_state.gyroscope[2];

    imu_message.linear_acceleration.x = message->imu_state.accelerometer[0];
    imu_message.linear_acceleration.y = message->imu_state.accelerometer[1];
    imu_message.linear_acceleration.z = message->imu_state.accelerometer[2];

    // Mark covariance as unknown until calibrated values are available.
    imu_message.orientation_covariance[0] = -1.0;
    imu_message.angular_velocity_covariance[0] = -1.0;
    imu_message.linear_acceleration_covariance[0] = -1.0;

    imu_publisher_->publish(imu_message);
  }

  rclcpp::Publisher<sensor_msgs::msg::Imu>::SharedPtr imu_publisher_;
  rclcpp::Subscription<unitree_go::msg::LowState>::SharedPtr low_state_subscription_;
};

int main(int argc, char * argv[])
{
  rclcpp::init(argc, argv);
  rclcpp::spin(std::make_shared<ImuPublisherNode>());
  rclcpp::shutdown();
  return 0;
}
