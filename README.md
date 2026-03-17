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

## 2. External Repos (`vcstool`)

`go2.repos` は外部リポジトリの一覧ファイル、`vcstool` はその一覧を一括取得・更新するためのコマンドです。
`FAST_LIO` / `livox_ros_driver2` などは、この組み合わせで管理します。

### mac での `vcstool` セットアップ (`uv`)

```bash
cd /Users/shibahara/Sandbox/go2-lab
uv init -p 3.12 .
uv tool install --with 'setuptools<81' vcstool
```

`uv` でインストールした場合の実行例:

```bash
cd /Users/shibahara/Sandbox/go2-lab
uvx vcs import --force < go2.repos
uvx vcs pull $(uvx vcs list < go2.repos)
```

### Jetson/Ubuntu での `vcstool` セットアップ

```bash
# 1) vcstool を入れる
sudo apt-get update
sudo apt-get install -y vcstool

# 2) このリポジトリのルートで実行
cd /home/unitree/go2-lab
vcs import --force < go2.repos
```

更新:

```bash
cd /home/unitree/go2-lab
vcs pull $(vcs list < go2.repos)
```

## 3. MID360 設定の反映

`configs/livox/MID360_config.json` を正として、利用前に `src/ros/livox_ros_driver2/config/` へ上書きします。

```bash
cd /home/unitree/go2-lab
cp configs/livox/MID360_config.json src/ros/livox_ros_driver2/config/MID360_config.json
```

## 4. Docker イメージ作成とビルド

デプロイ先ごとに `TARGET` を切り替えます。

### 4.1 コンテナ作成

```bash
cd /home/unitree/go2-lab

# Jetson 向け (fast-lio-ros2)
make build TARGET=jetson
make up TARGET=jetson
make shell TARGET=jetson

# 可視化PC向け (unitree_ros2-azure)
make build TARGET=desktop
make up TARGET=desktop
make shell TARGET=desktop
```

`src` 配下のデプロイ対象は以下のファイルで管理します。
- 共通: `configs/deploy/src-common.txt`
- Jetson固有差分: `configs/deploy/src-jetson.txt`
- desktop PC固有差分: `configs/deploy/src-desktop.txt`

`make src-list TARGET=<target>` は `common + target固有差分` の合成結果を表示します。
将来ターゲットを増やす場合は `configs/deploy/src-<new-target>.txt` を追加します。
（Docker コンテナ実行が必要なら `Makefile` に `PROFILE/SERVICES` の対応を追加）

確認/ステージング:

```bash
cd /home/unitree/go2-lab
make src-list TARGET=jetson
make src-stage TARGET=jetson STAGE_DIR=.staging/jetson
```

### 4.2 コンテナ内ビルド

コンテナ作成後、ROS パッケージのビルドと `zenoh-plugin-ros2dds` のビルドを順に実行します。
`zenoh` は `colcon build` とは別に Rust ワークスペースとしてビルドが必要です。

```bash
source /opt/ros/humble/setup.bash
cd /workspace
rm -rf build install log
make colcon-build TARGET=jetson
make zenoh-build TARGET=jetson
# desktop 側なら:
# make colcon-build TARGET=desktop
# make zenoh-build TARGET=desktop
source install/setup.bash
```

- `make colcon-build TARGET=<target>` は、対象ターゲットの ROS パッケージを `colcon build` します。
- `make zenoh-build TARGET=<target>` は、`zenoh-plugin-ros2dds` の Rust ワークスペースを `cargo build --release` します。
- `make zenoh-build` により、`zenoh-config-*.json` が参照する `src/zenoh-plugin-ros2dds/target/release/libzenoh_plugin_ros2dds.so` が生成されます。
- `make target-build TARGET=<target>` は、上記 2 手順をまとめて実行する補助コマンドです。

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
cd /home/unitree/go2-lab
make shell TARGET=jetson

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
