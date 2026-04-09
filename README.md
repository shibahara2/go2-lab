# go2-lab

このリポジトリは、犬ロボットPJの開発用ワークスペースです。  
セットアップ、設定同期、ビルド、起動確認までをまとめて扱えるようにしています。

## 目次

- [1. 構成](#1-構成)
- [2. clone](#2-clone)
- [3. 外部リポジトリ取得](#3-外部リポジトリ取得)
  - [3.1 uv](#31-uv)
  - [3.2 vcstool](#32-vcstool)
  - [3.3 go2.repos 取得](#33-go2repos-取得)
- [4. 実行環境構築](#4-実行環境構築)
  - [4.1 標準モード: workstation (`DISTRIBUTED_MODE=0`)](#41-標準モード-workstation-distributed_mode0)
  - [4.2 分散モード: robot + workstation + external router (`DISTRIBUTED_MODE=1`)](#42-分散モード-robot--workstation--external-router-distributed_mode1)
  - [4.3 共通](#43-共通)
- [5. パッケージビルド](#5-パッケージビルド)
- [6. 起動順](#6-起動順)
  - [6.1 標準モード (`DISTRIBUTED_MODE=0`)](#61-標準モード-distributed_mode0)
  - [6.2 分散モード (`DISTRIBUTED_MODE=1`)](#62-分散モード-distributed_mode1)
  - [6.3 Go2 IMU publisher](#63-go2-imu-publisher)
- [7. 環境変数と設定ファイル](#7-環境変数と設定ファイル)
  - [7.1 主要変数](#71-主要変数)
  - [7.2 `sync-configs` の生成対象](#72-sync-configs-の生成対象)
  - [7.3 zenoh client](#73-zenoh-client)
- [8. 構成を変更した場合](#8-構成を変更した場合)
- [9. 補足](#9-補足)
- [10. トラブルシュート](#10-トラブルシュート)
- [11. 参考資料](#11-参考資料)

## 1. 構成

登場する計算機は次の 2 種類です。

- `workstation`: 開発・ビルド・可視化を行う Linux PC
- `robot`: Go2 に搭載されている Docking Station (Jetson Orin NX)
- `router`: zenoh router を実行する PC

標準モードは `workstation` 単独運用です。
`robot` で publish される unitree_ros2 topic を扱いたい場合に分散モードを使います。
分散モードでは、`workstation` と `robot` で zenoh client を、`router` で zenoh router を実行します。

また、`robot` ではホストOSのバージョンが ROS の要求を満たさないため、コンテナ上で実行します。

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

### 4.2 分散モード: robot + workstation + external router (`DISTRIBUTED_MODE=1`)

分散モードでは `robot` と `workstation` の両方で clone を用意し、それぞれの `.env` を編集します。zenoh router はこの repo では管理せず、外部で起動済みのものに接続します。

`robot` 側:

- `DISTRIBUTED_MODE=1`
- `NETWORK_INTERFACE`: Go2 / MID360 と接続される Jetson 側 IF 名
- `ZENOH_ROUTER_IP`: 外部 router の IP
- `ROS_DOMAIN_ID`: workstation 側と揃える

設定を反映してコンテナを作成します。

```bash
make sync-configs
make build
make up
```

`workstation` 側:

- `DISTRIBUTED_MODE=1`
- `NETWORK_INTERFACE`: workstation Linux ホストで使う IF 名
- `ZENOH_ROUTER_IP`: 外部 router の IP
- `ROS_DOMAIN_ID`: robot 側と揃える

設定を反映します。

```bash
make sync-configs
```

router 側:
TODO

### 4.3 共通

初回のみ Livox SDK2 をインストールします。

```bash
make livox-sdk-install
```

## 5. パッケージビルド

### 5.1 workstation 側

`workstation` 側は、`./scripts/visualization_host_shell.sh` で開いたホスト用シェルの中でビルドします。

```bash
./scripts/visualization_host_shell.sh
make host-deps-install
make target-build
```

### 5.2 robot 側

`robot` 側は、`make shell` で Jetson コンテナに入ってからビルドします。

```bash
make shell
make target-build
```

### 5.3 関連コマンド

- `make target-build`: 常に `make colcon-build` を実行し、`DISTRIBUTED_MODE=1` のときだけ `make zenoh-build` を追加実行
- `make colcon-build`: `src/ros` 配下の ROS パッケージをビルド
- `make zenoh-build`: `src/zenoh` と `src/zenoh-plugin-ros2dds` を `cargo build --release`

## 6. 起動順

### 6.1 標準モード (`DISTRIBUTED_MODE=0`)

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

1. `robot` 側で zenoh client を起動する

```bash
make zenoh-client
```

1. `robot` 側で Go2 / MID360 に近いノードを起動する

```bash
ros2 launch livox_ros_driver2 msg_MID360_launch.py
ros2 launch fast_lio mapping.launch.py config_file:=mid360.yaml rviz:=false
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
source install/setup.bash
ros2 run imu_publisher imu_publisher
```

`robot` 側:

```bash
make shell
source install/setup.bash
ros2 run imu_publisher imu_publisher
```

確認例:

```bash
ros2 topic echo /go2/imu --once
```

## 7. 環境変数と設定ファイル

各 clone の `.env` から必要な設定を生成します。固定値だけの設定は `src/ros/...` を直接編集し、変数展開が必要な設定だけテンプレートから再生成します。

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

次のファイルはテンプレートから生成するため、実ファイルではなく `.tmpl` 側を編集してから再同期してください。`FAST_LIO` の設定は生成対象ではないので、`src/ros/FAST_LIO/config/mid360.yaml` を直接編集します。

| 入力ファイル | 出力先 | 使用する変数 |
|---|---|---|
| `src/ros/livox_ros_driver2/config/MID360_config.json.tmpl` | `src/ros/livox_ros_driver2/config/MID360_config.json` | `LIDAR_HOST_IP`, `LIDAR_DEVICE_IP` |
| `src/ros/unitree_ros2/setup.sh.tmpl` | `src/ros/unitree_ros2/setup.sh` | `NETWORK_INTERFACE`, `RMW_IMPLEMENTATION` |
| `configs/zenoh/zenoh-config-client.json.tmpl` | `configs/zenoh/zenoh-config-client.json` | `DISTRIBUTED_MODE=1` のときだけ `ZENOH_ROUTER_IP`, `ZENOH_ROUTER_PORT` |

### 7.3 zenoh client

- client 設定: `configs/zenoh/zenoh-config-client.json`

`make zenoh-client` は `DISTRIBUTED_MODE=1` のときだけ利用できます。.env を読み込み、`src/zenoh/target/release/zenohd -c configs/zenoh/zenoh-config-client.json` を起動します。

巨大な `PointCloud2` が congestion で drop される疑いがあるときは、`.env` に次を入れてから `make zenoh-client` を起動してください。

```bash
ZENOH_CONFIG_OVERRIDE=transport/link/tx/queue/congestion_control/drop/wait_before_drop=1000000
```

## 8. 構成を変更した場合

`.env` を編集したら、対象マシンで再度 `make sync-configs` を実行してください。

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
