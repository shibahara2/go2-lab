# SLAM
[Unitree Go2 Mid360でSLAMを実行する](https://techshare.co.jp/faq/unitree/mid360_slam_fast-lio.html)
- [x] macでimageをビルドできるか確認
- [x] macでコンテナ動作はできなかった: NVIDIA GPUがないから
- [ ] このリポジトリに入れる
- [ ] Jetsonでimageビルド、コンテナ実行できるか確認

# MEMO
- livox_ros_driver2をビルドしたい。build.shを使うと他のrosパッケージまで巻き込まれる。colcon buildにするとcmakeに適切な引数が渡らずエラーになる。

## fast-lio-ros2 (docker compose)

`fast-lio-ros2` コンテナを使って `FAST_LIO` と `livox_ros_driver2` をビルドする手順:

```bash
cd docker
docker compose build fast-lio-ros2
docker compose up -d fast-lio-ros2
docker compose exec fast-lio-ros2 bash
```

コンテナ内で実行:

```bash
cd /root/ros2_ws/src/livox_ros_driver2
source /opt/ros/humble/setup.bash
./build.sh humble

cd /root/ros2_ws
source install/setup.bash
colcon build --packages-select fast_lio --symlink-install
source install/setup.bash
```

起動例:

```bash
ros2 launch livox_ros_driver2 msg_MID360_launch.py
ros2 launch fast_lio mapping_mid360.launch.py
```
