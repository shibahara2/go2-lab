# go2-lab

このリポジトリは Go2 開発用ワークスペースです。  
role ごとに runtime を分け、設定同期、container 起動、ROS ビルド、分散接続をまとめて扱います。

## Runtime Model

- `robot`
  Go2 docking station 上の必須 runtime。Go2 / MID360 近傍ノードを動かす。ROS 2 Humble container。
- `workstation`
  Ubuntu Desktop 用の汎用 runtime。`unitree_ros2`、一般 ROS パッケージ、simulation、`zenoh-client` を含む。GUI は host、ROS 作業は Humble container。
- `dgx-spark`
  DGX Spark 用の複合 runtime。host は Jazzy 系を前提にし、container は 2 系統持つ。
- `dgx-spark-humble`
  ロボット側パッケージ互換用の Humble container。
- `dgx-spark-jazzy`
  Isaac ROS、local AI、voice teleop など GPU/Jazzy 用 container。
- `router`
  外部 zenoh router。repo 管理外。

## Clone

```bash
git clone <this-repo-url>
cd go2-lab
```

`workstation` だけを使う場合は 1 clone でよく、分散モードでは `robot` や `dgx-spark` 側にも clone を置きます。

## External Repos

```bash
uv tool install --with 'setuptools<81' vcstool
uvx --from vcstool vcs import --force < go2.repos
```

## Setup

まず `.env` を作ります。

```bash
cp .env.example .env
```

### Standard Mode

標準モードは `workstation` 単独です。

```bash
make sync-configs
make workstation-build
make workstation-up
```

GUI は host 側で扱います。

```bash
./scripts/visualization_host_shell.sh
rviz2
```

### Distributed Mode

分散モードは `DISTRIBUTED_MODE=1` で、`robot` と受け側 runtime を同じ `ROS_DOMAIN_ID` に揃えます。

共通で設定するもの:

- `NETWORK_INTERFACE`
- `ZENOH_ROUTER_IP`
- `ROS_DOMAIN_ID`

`robot` 側:

```bash
make sync-configs
make robot-build
make robot-up
```

`workstation` 側:

```bash
make sync-configs
make workstation-build
make workstation-up
```

`dgx-spark` 側:

```bash
make sync-configs
make dgx-spark-build
make dgx-spark-up
```

## Shell Entry

- `make robot-shell`
  `robot` container に入る
- `make workstation-shell`
  `workstation` container に入る
- `make dgx-spark-humble-shell`
  `dgx-spark-humble` container に入る
- `make dgx-spark-jazzy-shell`
  `dgx-spark-jazzy` container に入る
- `make dgx-spark-shell`
  `dgx-spark-jazzy-shell` の alias
- `./scripts/visualization_host_shell.sh`
  host GUI 用シェルを開く

各 container shell は ROS setup、`src/ros/unitree_ros2/setup.sh`、workspace overlay を自動 source します。

## Build

### Workstation

`workstation` では ROS 一式と simulation を container に寄せます。

```bash
make workstation-shell
make host-deps-install
make target-build
```

### Robot

```bash
make robot-shell
make host-deps-install
make target-build
```

### DGX Spark Humble

ロボット側パッケージ互換用です。

```bash
make dgx-spark-humble-shell
make host-deps-install
make target-build
```

### DGX Spark Jazzy

Isaac ROS、voice teleop、local AI 用です。

```bash
make dgx-spark-jazzy-shell
make zenoh-build
colcon build --packages-select voice_teleop
```

## Livox SDK2

Livox SDK2 は `robot` または Livox を直接扱う `workstation` / `dgx-spark-humble` でだけ使います。`dgx-spark-jazzy` では不要です。

```bash
make robot-shell
make livox-sdk-install
```

## Runtime Commands

- `make robot-build`, `make robot-up`, `make robot-down`
- `make workstation-build`, `make workstation-up`, `make workstation-down`
- `make dgx-spark-build`, `make dgx-spark-up`, `make dgx-spark-down`
- `make dgx-spark-humble-build`, `make dgx-spark-humble-up`, `make dgx-spark-humble-down`
- `make dgx-spark-jazzy-build`, `make dgx-spark-jazzy-up`, `make dgx-spark-jazzy-down`
- `make target-build`
  `colcon-build` に加え、`DISTRIBUTED_MODE=1` のときだけ `make zenoh-build`
- `make zenoh-client`
  `DISTRIBUTED_MODE=1` のときだけ実行可能

互換 alias:

- `make build/up/down/ps/logs/shell`
  既定では `robot-*` を指す

## Voice Teleop

`voice_teleop` は `dgx-spark-jazzy` で動かします。

前提:

- `robot` 側で `ros2 run cmd_vel_control cmd_vel_control` が起動済み
- `DISTRIBUTED_MODE=1`
- `robot` と `dgx-spark` 側で `make zenoh-client` が起動済み
- `VOICE_CAPTURE_DEV` と `VOICE_ASR_BACKEND` が `.env` に設定済み
- `parakeet` を使う場合は `VOICE_ASR_DEVICE`, `VOICE_ASR_MODEL`
- `azure` を使う場合は `AZURE_OPENAI_ENDPOINT`, `AZURE_OPENAI_API_KEY`, `AZURE_OPENAI_DEPLOYMENT_NAME`

起動:

```bash
make dgx-spark-jazzy-shell
make zenoh-client
ros2 run voice_teleop voice_teleop
```

`dgx-spark-jazzy` は GPU、音声デバイス、HuggingFace cache、Isaac ROS apt repo を持ちます。`dgx-spark-humble` とは責務を分けています。

## Environment Files

`.env` 変更後は `make sync-configs` を実行します。次のファイルが再生成されます。

- `src/ros/livox_ros_driver2/config/MID360_config.json`
  `LIDAR_HOST_IP`, `LIDAR_DEVICE_IP`
- `src/ros/unitree_ros2/setup.sh`
  `NETWORK_INTERFACE`, `RMW_IMPLEMENTATION`
- `configs/zenoh/zenoh-config-client.json`
  `DISTRIBUTED_MODE=1` のときだけ `ZENOH_ROUTER_IP`, `ZENOH_ROUTER_PORT`

## Notes

- `robot` と `workstation` は Humble runtime
- `dgx-spark` は Humble と Jazzy の両 runtime を持つ
- GUI は host に残し、ROS 作業は container に寄せる
- `dgx-spark-jazzy` だけが `gpus: all` を要求する

## Troubleshooting

### `make zenoh-client` が拒否される

`DISTRIBUTED_MODE=1` を `.env` に設定して `make sync-configs` を再実行してください。

### `ros2 topic list` が空

- `NETWORK_INTERFACE` が正しいか確認する
- `ROS_DOMAIN_ID` を各 clone で揃える
- 分散モードでは双方で `make zenoh-client` を起動する
- 外部 zenoh router に到達できるか確認する

### `unitree_ros2` topic が見えない

`src/ros/unitree_ros2/setup.sh` に反映された `NETWORK_INTERFACE` を確認し、必要なら `ros2 daemon stop` で discovery キャッシュを消して再確認してください。

### RViz で点群が出ない

- Fixed Frame を `camera_init` にする
- `/cloud_registered` が publish されているか確認する
- `ros2 topic echo /Odometry --once` が通るか確認する

## References

- TechShare: <https://techshare.co.jp/faq/unitree/mid360_slam_fast-lio.html>
- zenoh plugin for ROS 2 DDS: <https://github.com/eclipse-zenoh/zenoh-plugin-ros2dds>
