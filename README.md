# Go2 + MID360 + FAST-LIO(ROS2)

このリポジトリは、Go2 / MID360 / FAST-LIO の開発用ワークスペースです。  
標準運用では `workstation` Linux ホスト上で ROS を動かし、必要なときだけ `jetson` コンテナを使います。

このリポジトリは zenoh client 側の build / config / 起動導線は持ちますが、zenoh router 自体はこのリポジトリでは管理しません。分散モードでは外部で用意した router に接続します。

## はじめに

最短で環境を立ち上げる場合は、次の順で進めます。

```bash
git clone <this-repo-url>
cd go2-lab
cp .env.example .env
make sync-configs
make host-deps-install
make colcon-build
./scripts/visualization_host_shell.sh
```

詳細は以下を参照してください。

- 構成と対象マシン: [1. 構成](#1-構成)
- 外部依存の取得: [3. 外部リポジトリ取得](#3-外部リポジトリ取得)
- 環境構築と起動: [4. 実行環境構築](#4-実行環境構築), [6. 起動順](#6-起動順)

## 1. 構成

登場する計算機は次の 2 種類です。

- `workstation`: 開発・ビルド・可視化を行う Linux PC
- `robot`: Go2 に搭載されている Docking Station (Jetson Orin NX)

標準構成は `workstation` 単独運用です。Go2 実機や MID360 に近いノードを Jetson 側で動かし、topic を `workstation` へ中継したいときだけ分散モードを使います。

Docker を使うのは `robot` 側の `jetson` コンテナだけです。`workstation` 側はホスト Linux 上で作業します。

## 2. clone

```bash
git clone <this-repo-url>
cd go2-lab
```

標準モードでは `workstation` に clone するだけで構いません。分散モードを使う場合は `robot` にも clone を用意してください。

## 3. 外部リポジトリ取得

本リポジトリと分けて管理するリポジトリを `go2.repos` に記載しています。これらを `vcstool` で取得・管理し、本リポジトリでは追跡しません。

### 3.1 uv

`vcstool` の導入には `uv` を使います。

[公式ドキュメント](https://docs.astral.sh/uv/getting-started/installation/) に従ってインストールしてください。

### 3.2 vcstool

```bash
uv tool install --with 'setuptools<81' vcstool
```

### 3.3 go2.repos 取得

```bash
uvx --from vcstool vcs import --force < go2.repos
```

## 4. 実行環境構築

`.env.example` を `.env` にコピーします。

```bash
cp .env.example .env
```

### 4.1 標準モード: workstation (`DISTRIBUTED_MODE=0`)

標準モードでは `workstation` の `.env` を用意し、設定を反映します。

```bash
cp .env.example .env
make sync-configs
```

最低限確認する値:

- `NETWORK_INTERFACE`: workstation Linux ホスト上で実在する IF 名
- `LIDAR_HOST_IP`, `LIDAR_DEVICE_IP`: MID360 実配線に合わせた IP
- `ROS_DOMAIN_ID`, `RMW_IMPLEMENTATION`: この clone で使う ROS 2 設定

### 4.2 分散モード: robot + workstation + external router (`DISTRIBUTED_MODE=1`)

分散モードでは `robot` と `workstation` の両方で clone を用意し、それぞれの `.env` を編集します。zenoh router はこの repo では管理せず、外部で起動済みのものに接続します。

`robot` 側:

- `DISTRIBUTED_MODE=1`
- `NETWORK_INTERFACE`: Go2 / MID360 と接続される Jetson 側 IF 名
- `ZENOH_ROUTER_IP`: 外部 router の IP
- `ROS_DOMAIN_ID`: workstation 側と揃える

```bash
make sync-configs
make build
make up
make shell
```

`workstation` 側:

- `DISTRIBUTED_MODE=1`
- `NETWORK_INTERFACE`: workstation Linux ホストで使う IF 名
- `ZENOH_ROUTER_IP`: 外部 router の IP
- `ROS_DOMAIN_ID`: robot 側と揃える

```bash
make sync-configs
```

### 4.3 共通

初回のみ Livox SDK2 をインストールします。

```bash
make livox-sdk-install
```

## 5. パッケージビルド

利用する実行導線は次の 2 つです。

- `make shell`: `robot` 上の Jetson コンテナに入る
- `./scripts/visualization_host_shell.sh`: `workstation` Linux ホスト上の可視化用シェルを開く

`workstation` 側は基本的にホストでビルドします。

```bash
make host-deps-install
make colcon-build
```

`robot` 側は Jetson コンテナに入ってビルドします。

```bash
make shell
make target-build
```

`make target-build` の中身:

- 常に `make colcon-build` を実行する
- `DISTRIBUTED_MODE=1` のときだけ `make zenoh-build` を追加実行する

関連コマンド:

- `make colcon-build`: `src/ros` 配下の ROS パッケージをビルド
- `make zenoh-build`: `src/zenoh` と `src/zenoh-plugin-ros2dds` を `cargo build --release`

## 6. 起動順

### 6.1 標準モード (`DISTRIBUTED_MODE=0`)

1. `workstation` で ROS パッケージをビルドする

```bash
make colcon-build
```

1. Livox ドライバを起動する

```bash
ros2 launch livox_ros_driver2 msg_MID360_launch.py
```

1. FAST-LIO を起動する

```bash
ros2 launch fast_lio mapping.launch.py config_file:=mid360.yaml rviz:=false
```

1. topic と RViz を確認する

```bash
ros2 topic list
ros2 topic echo /Odometry --once
./scripts/visualization_host_shell.sh
rviz2
```

RViz の目安:

- Fixed Frame: `camera_init`
- 表示候補: `/cloud_registered`, `/Odometry`, `/tf`, `/tf_static`

### 6.2 分散モード (`DISTRIBUTED_MODE=1`)

1. `robot` 側でコンテナに入り、ビルドする

```bash
make shell
make target-build
```

1. `robot` 側で zenoh client を起動する

```bash
make zenoh-client
```

1. `robot` 側で Go2 / MID360 に近いノードを起動する

```bash
ros2 launch livox_ros_driver2 msg_MID360_launch.py
ros2 launch fast_lio mapping.launch.py config_file:=mid360.yaml rviz:=false
```

1. `workstation` 側でビルドする

```bash
make colcon-build
```

1. `workstation` 側で zenoh client を起動する

```bash
make zenoh-client
```

1. `workstation` 側で topic と RViz を確認する

```bash
ros2 topic list
ros2 topic echo /Odometry --once
./scripts/visualization_host_shell.sh
rviz2
```

### 6.3 Go2 IMU publisher

Go2 の `/lowstate` を `sensor_msgs/msg/Imu` に変換して `/go2/imu` へ配信します。標準フローには必須ではありませんが、必要なら `workstation` ホストまたは `jetson` コンテナで起動できます。

`workstation` 側:

```bash
make colcon-build
source install/setup.bash
ros2 run imu_publisher imu_publisher
```

`robot` 側:

```bash
make shell
make colcon-build
source install/setup.bash
ros2 run imu_publisher imu_publisher
```

確認例:

```bash
ros2 topic echo /go2/imu --once
```

## 7. 環境変数と設定ファイル

各 clone の `.env` から設定を生成します。`configs/fast_lio/mid360.yaml` は変数展開なしでそのまま同期されます。

### 7.1 主要変数

| 変数 | 反映先 | 用途 |
|---|---|---|
| `DISTRIBUTED_MODE` | `Makefile`, `scripts/run_zenoh_client.sh`, `scripts/sync_configs.sh` | `0` は標準モード、`1` は分散モード |
| `ZENOH_ROUTER_IP` | `configs/zenoh/zenoh-config-client.json` | 分散モード時の zenoh client 接続先 IP |
| `ZENOH_ROUTER_PORT` | `configs/zenoh/zenoh-config-client.json` | 分散モード時の zenoh 接続ポート |
| `ZENOH_CONFIG_OVERRIDE` | `make zenoh-client` 実行時の環境変数 | zenoh の transport override |
| `NETWORK_INTERFACE` | `src/ros/unitree_ros2/setup.sh` | CycloneDDS の `NetworkInterface name` |
| `LIDAR_HOST_IP` | `src/ros/livox_ros_driver2/config/MID360_config.json` | LiDAR 受信先 IP |
| `LIDAR_DEVICE_IP` | `src/ros/livox_ros_driver2/config/MID360_config.json` | LiDAR 本体 IP |
| `RMW_IMPLEMENTATION` | `src/ros/unitree_ros2/setup.sh`, `scripts/visualization_host_shell.sh` | ROS 2 ミドルウェア実装 |
| `ROS_DOMAIN_ID` | `scripts/visualization_host_shell.sh` | ROS 2 ドメイン ID |
| `DOCKER_SHM_SIZE` | `.env.example` | Docker 用の共有メモリサイズ設定 |
| `LIDAR_DATASET_PATH` | `.env.example` | 任意データパスの予約変数 |

### 7.2 `sync-configs` の生成対象

次のファイルは `configs/` から生成または同期するため、展開先ではなく `configs/` 側を編集してから再同期してください。

| 入力ファイル | 出力先 | 使用する変数 |
|---|---|---|
| `configs/livox/MID360_config.json` | `src/ros/livox_ros_driver2/config/MID360_config.json` | `LIDAR_HOST_IP`, `LIDAR_DEVICE_IP` |
| `configs/fast_lio/mid360.yaml` | `src/ros/FAST_LIO/config/mid360.yaml` | なし |
| `configs/unitree_ros2/setup.sh` | `src/ros/unitree_ros2/setup.sh` | `NETWORK_INTERFACE`, `RMW_IMPLEMENTATION` |
| `configs/zenoh/zenoh-config-client.json.tmpl` | `configs/zenoh/zenoh-config-client.json` | `DISTRIBUTED_MODE=1` のときだけ `ZENOH_ROUTER_IP`, `ZENOH_ROUTER_PORT` |

```bash
make sync-configs
```

### 7.3 zenoh client

- client 設定: `configs/zenoh/zenoh-config-client.json`

`make zenoh-client` は `DISTRIBUTED_MODE=1` のときだけ利用できます。.env を読み込み、`src/zenoh/target/release/zenohd -c configs/zenoh/zenoh-config-client.json` を起動します。

巨大な `PointCloud2` が congestion で drop される疑いがあるときは、`.env` に次を入れてから `make zenoh-client` を起動してください。

```bash
ZENOH_CONFIG_OVERRIDE=transport/link/tx/queue/congestion_control/drop/wait_before_drop=1000000
```

## 8. 構成を変更した場合

`.env` を編集したら、対象マシンで再度 `make sync-configs` を実行してください。

```bash
make sync-configs
```

## 9. 補足

Jetson で複数ターミナルを開いて作業する場合は、SSH multiplexing や zellij レイアウトを使うと運用しやすくなります。ただし、これらは本リポジトリの必須要件ではありません。

## 10. トラブルシュート

### zenoh client 起動時に `does not match an available interface` で落ちる

例:

```text
eno1: does not match an available interface
Failed to create RosDiscoveryInfoMgr
Error creating DDS Reader on ros_discovery_info: Precondition Not Met
```

これは zenoh の接続先設定ではなく、CycloneDDS が `NETWORK_INTERFACE` に指定された IF 名を見つけられないときに起きます。

```bash
ip link show
# または
ifconfig
```

`.env` の `NETWORK_INTERFACE` を実在する IF 名に直し、再度 `make sync-configs` を実行してください。

### `ros2 topic list` が空

- 標準モードでは `NETWORK_INTERFACE` が正しいか確認する
- 分散モードでは `robot` 側と `workstation` 側で `ROS_DOMAIN_ID` を一致させる
- 分散モードでは両方の `.env` で `RMW_IMPLEMENTATION` を一致させる
- 分散モードでは両方で `make zenoh-client` が起動しているか確認する
- 分散モードでは外部 zenoh router に到達できるか確認する

### `/livox/lidar` が出ない

- `MID360_config.json` の IP 設定を実機ネットワークに合わせる
- LiDAR と接続ホストの L2 疎通を確認する

### RViz で点群が出ない

- Fixed Frame を `camera_init` にする
- `/cloud_registered` が publish されているか確認する
- `ros2 topic echo /Odometry --once` が通るか確認する

### `unitree_ros2` topic が見えない

- `src/ros/unitree_ros2/setup.sh` に反映された `NETWORK_INTERFACE` を確認する
- `ros2 daemon stop` で discovery キャッシュを消してから再確認する

## 11. 参考資料

- TechShare: <https://techshare.co.jp/faq/unitree/mid360_slam_fast-lio.html>
- zenoh plugin for ROS 2 DDS: <https://github.com/eclipse-zenoh/zenoh-plugin-ros2dds>
