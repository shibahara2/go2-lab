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
  - [4.2 分散モード: robot + workstation/dgx-spark + external router (`DISTRIBUTED_MODE=1`)](#42-分散モード-robot--workstationdgx-spark--external-router-distributed_mode1)
  - [4.3 共通](#43-共通)
- [5. パッケージビルド](#5-パッケージビルド)
- [6. 起動順](#6-起動順)
  - [6.1 標準モード (`DISTRIBUTED_MODE=0`)](#61-標準モード-distributed_mode0)
  - [6.2 分散モード (`DISTRIBUTED_MODE=1`)](#62-分散モード-distributed_mode1)
  - [6.3 Go2 IMU publisher](#63-go2-imu-publisher)
  - [6.4 音声 teleop (voice_teleop)](#64-音声-teleop-voice_teleop)
- [7. 環境変数と設定ファイル](#7-環境変数と設定ファイル)
  - [7.1 主要変数](#71-主要変数)
  - [7.2 `.env` 変更後の `sync-configs`](#72-env-変更後の-sync-configs)
- [8. 補足](#8-補足)
- [9. トラブルシュート](#9-トラブルシュート)
- [10. 参考資料](#10-参考資料)

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

### 4.2 分散モード: robot + workstation/dgx-spark + external router (`DISTRIBUTED_MODE=1`)

分散モードでは `robot` と、ROS topic を利用する受け側 (`workstation` ホストまたは `dgx-spark` コンテナを動かすマシン) の両方で clone を用意し、それぞれの `.env` を編集します。zenoh router はこの repo では管理せず、外部で起動済みのものに接続します。受け側は `workstation` と `dgx-spark` で手順が異なります。

`robot` 側:

- `DISTRIBUTED_MODE=1`
- `NETWORK_INTERFACE`: Go2 / MID360 と接続される Jetson 側 IF 名
- `ZENOH_ROUTER_IP`: 外部 router の IP
- `ROS_DOMAIN_ID`: 選んだ受け側 (`workstation` または `dgx-spark`) と揃える

設定を反映してコンテナを作成します。

```bash
make sync-configs
make build
make up
```

`workstation` 側:

- `DISTRIBUTED_MODE=1`
- `NETWORK_INTERFACE`: topic を publish / subscribe する側 Linux 環境で使う IF 名
- `ZENOH_ROUTER_IP`: 外部 router の IP
- `ROS_DOMAIN_ID`: robot 側と揃える

設定だけ反映します。

```bash
make sync-configs
```

`dgx-spark` 側:

- `DISTRIBUTED_MODE=1`
- `NETWORK_INTERFACE`: topic を publish / subscribe する側 Linux 環境で使う IF 名
- `ZENOH_ROUTER_IP`: 外部 router の IP
- `ROS_DOMAIN_ID`: robot 側と揃える

`dgx-spark` は専用コンテナを使うため、設定反映に加えて `make build` / `make up` ではなく `make dgx-spark-build` / `make dgx-spark-up` を使います。Compose 定義も Jetson 用と分離してあり、Jetson 側の `make build` が `dgx-spark` の GPU 設定を検証して失敗することはありません。

```bash
make sync-configs
make dgx-spark-build
make dgx-spark-up
```

router 側:
TODO

### 4.3 共通

初回のみ Livox SDK2 をインストールします。対象は `robot` または Livox を直接扱う `workstation` で、`dgx-spark` では実行しません。`workstation` ではホスト用シェルから実行し、`robot` では Jetson ホストではなく `make shell` で入った Jetson コンテナ内で実行します。

```bash
make livox-sdk-install
```

`robot` 側の例:

```bash
make shell
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
make host-deps-install
make target-build
```

### 5.3 dgx-spark 側

`dgx-spark` 側は専用コンテナに入り、その中で必要なビルドだけを実行します。通常は `voice_teleop` を `packages-select` で対象指定し、必要に応じて `zenoh` 関連だけを追加でビルドします。Livox や robot 近傍ノードのセットアップは行いません。

```bash
make dgx-spark-shell
colcon build \
  --packages-select voice_teleop \
make zenoh-build
```

### 5.4 関連コマンド

- `make target-build`: 常に `make colcon-build` を実行し、`DISTRIBUTED_MODE=1` のときだけ `make zenoh-build` を追加実行
- `make colcon-build`: `src/ros` 配下の ROS パッケージをビルド
- `make zenoh-build`: `src/zenoh` と `src/zenoh-plugin-ros2dds` を `cargo build --release`
- `make host-deps-install`: `configs/deps/packages.txt` の共通 apt パッケージに加え、`src/ros` 配下の各 `package.xml` を `rosdep install` で解決する
- `make dgx-spark-shell`: `dgx-spark` コンテナに入り、`/opt/ros/jazzy/setup.zsh` と workspace overlay を auto-source した状態でシェルを開く
- `make dgx-spark-shell` の中では `make zenoh-build` / `make zenoh-client` も実行可能

### 5.5 Python ノードを追加するときの依存の書き方

Python ノード固有の実行時依存 (PyPI ライブラリ相当 / apt 系ツール) は、そのパッケージの `package.xml` に `<exec_depend>` として rosdep キーで書きます (例: `python3-websockets`, `alsa-utils`)。`configs/deps/packages.txt` には書きません。`make host-deps-install` が `rosdep install --from-paths src/ros` を呼ぶため、package.xml 側の宣言だけで workstation / Jetson どちらにもインストールされます。rosdep で解決できないライブラリが必要になった場合は、方針転換として ADR を起票してください。背景は `docs/adr/0002-python-deps.md` を参照。

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

1. `workstation` または `dgx-spark` 側で zenoh client を起動する

```bash
make zenoh-client
```

1. `workstation` または `dgx-spark` 側で topic を確認する

```bash
ros2 topic list
ros2 topic echo /Odometry --once
```

`workstation` で可視化する場合:

```bash
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

### 6.4 音声 teleop (voice_teleop)

`dgx-spark` コンテナ内で発話から `geometry_msgs/Twist` を `/cmd_vel` に publish します。STT backend はローカル NVIDIA Parakeet (`nvidia/parakeet-tdt_ctc-0.6b-ja`) と Azure OpenAI Realtime API を `VOICE_ASR_BACKEND` で切り替えできます。`parakeet` はローカル transcript をキーワード判定して `/cmd_vel` を出し、`azure` は Realtime API の STT -> LLM -> function calling で `step_forward` / `stop_robot` を選び、日本語の短い assistant reply をテキスト+音声で返します。`cmd_vel_control` が `/cmd_vel` を `/api/sport/request` に変換するため、DGX Spark 側で本ノードを動かし、`robot` 側で `cmd_vel_control` を起動することで Go2 が動きます。設計の背景は `docs/adr/0001-voice-teleop.md` を参照してください。

前提:

- `DISTRIBUTED_MODE=1` の分散モードで `robot` 側と `dgx-spark` 側の zenoh-client、および external router が稼働中
- `robot` 側で `ros2 run cmd_vel_control cmd_vel_control` が起動済み
- Go2 の sport_mode が操作可能な状態 (アンロック) になっていること
- `.env` に `VOICE_CAPTURE_DEV`, `VOICE_ASR_BACKEND` が設定済み
- `VOICE_ASR_BACKEND=parakeet` の場合は `VOICE_ASR_DEVICE`, `VOICE_ASR_MODEL` が設定済み
- `VOICE_ASR_BACKEND=azure` の場合は `AZURE_OPENAI_ENDPOINT`, `AZURE_OPENAI_API_KEY`, `AZURE_OPENAI_DEPLOYMENT_NAME` が設定済み
- `VOICE_ASR_BACKEND=azure` で音声応答も使う場合は `aplay` で再生可能な出力デバイスが利用可能
- `arecord -l` で USB マイクの ALSA デバイス名を確認し `VOICE_CAPTURE_DEV` に反映
- `make dgx-spark-build && make dgx-spark-up` が済んでいる
- `make dgx-spark-shell` に入って `make zenoh-build` を一度実行済み

疎通確認 (voice_teleop 起動前):

```bash
ros2 topic pub --once /cmd_vel geometry_msgs/msg/Twist '{linear: {x: 0.3}}'
```

起動 (`dgx-spark` コンテナ):

```bash
make dgx-spark-shell
make zenoh-client
ros2 run voice_teleop voice_teleop
```

対応コマンドは backend 共通で「前進」と「止まって」だけです。`parakeet` は transcript をローカル判定して `step_forward` / `stop_robot` 相当の動作を実行し、`azure` は Azure Realtime の server VAD と function calling で同じ 2 アクションを呼び分けます。`step_forward` は約 0.3 秒の短い前進パルスを出した後、停止 `Twist` を複数回 publish して確実に止めます。assistant は短い日本語応答をテキスト+音声で返します。

比較時は `.env` の `VOICE_ASR_BACKEND` を切り替えて同じ手順を繰り返します。`parakeet` は `backend=...`, `stt_latency_ms=...`, `cmd_latency_ms=...`, `command=...`, `transcript=...` を 1 発話ごとに出します。`azure` は `azure_input_transcript`, `azure_tool_call`, `azure_response_done` を出すため、STT 結果・実行 tool・assistant reply を同一発話単位で確認できます。

`dgx-spark` image の ROS 2 Jazzy は Ubuntu 24.04/Noble 向けの公式手順に合わせて `universe` + `ros2-apt-source` で導入しています。加えて、将来 NVIDIA Isaac ROS パッケージを追加できるよう、NVIDIA の Isaac ROS apt repository と rosdep 定義も image 内に登録済みです。`voice_teleop` 自体は Isaac ROS 非依存ですが、DGX Spark 上の GPU ノードを今後増やすときの基盤として扱います。分散モードで DGX Spark 側から topic を publish / subscribe するため、image には `cargo` / `rustc` などの Rust toolchain も入っており、`make dgx-spark-shell` の中で `make zenoh-build` / `make zenoh-client` をそのまま実行できます。

`dgx-spark` コンテナ内で ROS コマンドを使う場合は、素の `docker exec` ではなく `make dgx-spark-shell` を使ってください。ROS 2 と `install/setup.zsh` が自動で source されます。

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

### 7.2 `.env` 変更後の `sync-configs`

設定値を変えるときは、まず `.env` を編集し、その後に対象マシンで `make sync-configs` を実行します。すると、次のファイルが `.env` の値を使ってテンプレートから更新されます。テンプレートの構造や固定文言を変えたい場合だけ `.tmpl` 側を編集してください。

| 入力ファイル | 出力先 | 使用する変数 |
|---|---|---|
| `src/ros/livox_ros_driver2/config/MID360_config.json.tmpl` | `src/ros/livox_ros_driver2/config/MID360_config.json` | `LIDAR_HOST_IP`, `LIDAR_DEVICE_IP` |
| `src/ros/unitree_ros2/setup.sh.tmpl` | `src/ros/unitree_ros2/setup.sh` | `NETWORK_INTERFACE`, `RMW_IMPLEMENTATION` |
| `configs/zenoh/zenoh-config-client.json.tmpl` | `configs/zenoh/zenoh-config-client.json` | `DISTRIBUTED_MODE=1` のときだけ `ZENOH_ROUTER_IP`, `ZENOH_ROUTER_PORT` |

## 8. 補足

Jetson で複数ターミナルを開いて作業する場合は、SSH multiplexing や zellij レイアウトを使うと運用しやすくなります。ただし、これらは本リポジトリの必須要件ではありません。

Jetson 系コマンド (`make build`, `make up`, `make shell`) は `docker/docker-compose.yml` だけを参照します。DGX Spark 系コマンド (`make dgx-spark-build`, `make dgx-spark-up`) は追加の Compose 定義 `docker/docker-compose.dgx-spark.yml` を重ねて読み込みます。

DGX Spark プロファイル (`make dgx-spark-build`, `make dgx-spark-up`) は Docker Compose の GPU 要求 (`gpus: all`) を使います。ホスト側では NVIDIA driver と Docker の GPU 連携が有効である必要がありますが、Docker daemon に `nvidia` runtime 名を登録しておく必要はありません。

## 9. トラブルシュート

### zenoh client を起動したい

- client 設定は `configs/zenoh/zenoh-config-client.json`
- `make zenoh-client` は `DISTRIBUTED_MODE=1` のときだけ利用可能
- `.env` を読み込み、`src/zenoh/target/release/zenohd -c configs/zenoh/zenoh-config-client.json` を起動する

巨大な `PointCloud2` が congestion で drop される疑いがあるときは、`.env` に次を入れてから `make zenoh-client` を起動してください。

```bash
ZENOH_CONFIG_OVERRIDE=transport/link/tx/queue/congestion_control/drop/wait_before_drop=1000000
```

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

## 10. 参考資料

- TechShare: <https://techshare.co.jp/faq/unitree/mid360_slam_fast-lio.html>
- zenoh plugin for ROS 2 DDS: <https://github.com/eclipse-zenoh/zenoh-plugin-ros2dds>
