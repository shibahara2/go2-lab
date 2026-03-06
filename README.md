# Go2 + MID360 + FAST-LIO(ROS2) + RViz(遠隔PC)

このリポジトリは、Unitree Go2 (Jetson) 上で FAST-LIO(ROS2) を実行し、
VPN/インターネット越しに別PC(Ubuntu)の RViz2 で可視化するための手順をまとめています。

参照:
- https://techshare.co.jp/faq/unitree/mid360_slam_fast-lio.html
- https://github.com/eclipse-zenoh/zenoh-plugin-ros2dds

## 1. 構成

- SLAM実行: Go2 Jetson (`fast-lio-ros2` コンテナ)
- 可視化: Ubuntu PC (`rviz2`)
- 中継: zenoh (`zenohd + ros2dds plugin`)

VPN/インターネット越しでは DDS 直結が難しいため、`zenoh` ブリッジ構成を使います。

## 2. 依存レポジトリ管理 (`go2.repos`)

`FAST_LIO` は ROS1 版から ROS2 fork に置換済みです。

- `src/ros/FAST_LIO`
  - url: `https://github.com/Ericsii/FAST_LIO_ROS2.git`
  - version: `2fffc570a25d0df172720bac034fbdb6a13d2162`

取得/更新:

```bash
cd /home/unitree/go2-lab
vcs import --force < go2.repos
vcs pull $(vcs list < go2.repos)
```

補足:
- 既存の `src/ros/FAST_LIO` が ROS1 版のままなら、`vcs import --force` で置換されます。

## 3. MID360 設定の反映

```bash
cd /home/unitree/go2-lab
cp configs/livox/MID360_config.json src/ros/livox_ros_driver2/config/MID360_config.json
```

## 4. Docker イメージ作成とビルド

```bash
cd /home/unitree/go2-lab/docker
docker compose build fast-lio-ros2
docker compose up -d fast-lio-ros2
docker compose exec fast-lio-ros2 bash
```

コンテナ内:

```bash
source /opt/ros/humble/setup.bash
cd /workspace
rm -rf build install log
colcon build --base-paths src/ros --symlink-install --packages-skip turtlesim
source install/setup.bash
```

## 5. 環境変数 (Jetson/可視化PC 共通)

両端で以下を合わせる:

```bash
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export ROS_LOCALHOST_ONLY=1
export ROS_DOMAIN_ID=0
```

- `ROS_DOMAIN_ID` は Jetson と可視化PCで必ず同じ値にします。
- DDSループ防止のため、`ROS_LOCALHOST_ONLY=1` を使います。

## 6. 起動順

### 6.1 可視化PC (Ubuntu): zenoh router 起動

```bash
cd ~/go2-lab
zenohd -c zenoh-config-azure.json
```

> `zenohd` バイナリが無い場合は、zenoh の公式手順で導入してください。

### 6.2 Jetson: FAST-LIO コンテナへ入り ROS2環境読み込み

```bash
cd /home/unitree/go2-lab/docker
docker compose exec fast-lio-ros2 bash

source /opt/ros/humble/setup.bash
source /workspace/install/setup.bash
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export ROS_LOCALHOST_ONLY=1
export ROS_DOMAIN_ID=0
```

### 6.3 Jetson: Livoxドライバ起動

```bash
ros2 launch livox_ros_driver2 msg_MID360_launch.py
```

### 6.4 Jetson: FAST-LIO(ROS2) 起動 (Go2側でRVizは起動しない)

別ターミナルで同じ環境を読み込み:

```bash
ros2 launch fast_lio mapping.launch.py config_file:=mid360.yaml rviz:=false
```

### 6.5 Jetson: zenoh client 起動

別ターミナルで同じ環境を読み込み:

```bash
cd /home/unitree/go2-lab
zenohd -c zenoh-config-jetson.json
```

### 6.6 可視化PC: トピック確認後に RViz2 起動

```bash
ros2 topic list
ros2 topic echo /Odometry --once
rviz2
```

RVizの目安:
- Fixed Frame: `camera_init`
- 表示候補:
  - `/cloud_registered`
  - `/Odometry`
  - `/tf`
  - `/tf_static`

## 7. 疎通/動作確認

### Jetson単体

```bash
ros2 topic list
ros2 topic hz /livox/lidar
ros2 topic hz /Odometry
```

### VPN越し中継

可視化PCで:

```bash
ros2 topic list
ros2 topic echo /Odometry --once
```

### RViz

- 点群とオドメトリが連続更新されること
- 5分以上連続で途切れないこと

## 8. zenoh 設定ファイル

- Jetson(client): `zenoh-config-jetson.json`
  - `connect.endpoints`: `tcp/135.149.56.251:7447`
  - `plugins.ros2dds.domain`: `0`
  - `plugins.ros2dds.ros_localhost_only`: `true`

- 可視化PC(router): `zenoh-config-azure.json`
  - `listen.endpoints`: `tcp/0.0.0.0:7447`
  - `plugins.ros2dds.domain`: `0`
  - `plugins.ros2dds.ros_localhost_only`: `true`

## 9. トラブルシュート

- `ros2 topic list` が空:
  - Jetson/可視化PCの `ROS_DOMAIN_ID` 不一致を確認
  - `RMW_IMPLEMENTATION=rmw_cyclonedds_cpp` が両端で有効か確認
  - `zenohd` 起動ログで接続断を確認

- `/livox/lidar` が出ない:
  - `MID360_config.json` の IP/Port を実機ネットワークに合わせる
  - LiDARとJetsonのL2疎通を確認

- RVizで点群が出ない:
  - Fixed Frame を `camera_init` に設定
  - `/cloud_registered` の QoS を確認
