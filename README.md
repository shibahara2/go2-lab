# Go2 + MID360 + FAST-LIO(ROS2) + RViz(Host GUI)

このリポジトリは、Unitree Go2 (Jetson) 上で FAST-LIO(ROS2) を実行し、
VPN/インターネット越しに別PC(Ubuntu)のホスト環境で RViz2 を可視化するための手順をまとめています。

参照:

- <https://techshare.co.jp/faq/unitree/mid360_slam_fast-lio.html>
- <https://github.com/eclipse-zenoh/zenoh-plugin-ros2dds>

## 1. 構成

- SLAM実行: Go2 Jetson (`jetson` コンテナ)
- 中継: Ubuntu PC (`bridge` コンテナ上の `zenohd + ros2dds plugin`)
- 可視化: Ubuntu PC ホスト (`rviz2`)

VPN/インターネット越しでは DDS 直結が難しいため、`zenoh` ブリッジ構成を使います。

## 2. clone

```bash
git clone <this-repo-url>
cd go2-lab
```

## 3. 外部リポジトリ取得

依存する外部リポジトリを取得します。
`go2.repos` は外部リポジトリの一覧ファイルです。
`vcstool` を用いてその一覧を取得・更新します。

### 3.1 uv

`vcstool`をインストールするために、Rust製のPythonパッケージ管理ツールである`uv`を利用します。
`
[公式ドキュメント](https://docs.astral.sh/uv/getting-started/installation/)に従ってインストールしてください。

### 3.2 vcstool

```bash
uv tool install --with 'setuptools<81' vcstool
```

`uv tool install ...` でインストールした `vcstool`は、このプロジェクト配下ではなくユーザー環境に入ります。
このリポジトリを Python プロジェクトとして初期化する必要はありません。

### 3.3 go2.repos取得

`go2.repos` にある外部リポジトリを取得します。

```bash
uvx --from vcstool vcs import --force < go2.repos
```

`uvx` は `uv tool run` のエイリアスです。

## 4. 実行環境構築

`TARGET` は `jetson` / `bridge` / `visualization-host` の配備対象を表します。
このうち Docker で管理するのは `jetson` と `bridge` のみです。
`visualization-host` はホスト上でネイティブに運用します。
初回セットアップ時は、`configs/` 配下の正本を `src/` 配下へ反映するために `make sync-configs TARGET=<target>` を先に実行します。
各ホストの設定は単一の `.env` で管理します。
`TARGET` は env ファイルの切り替えではなく、同期先と実行対象の切り替えにだけ使います。
`configs/fast_lio/mid360.yaml` は target 非依存の共有設定として同じ内容を同期します。

初回は `.env.example` を `.env` にコピーして必要に応じて編集してください。

| ターゲット | 使う env | `NETWORK_INTERFACE` の考え方 |
|---|---|---|
| jetson | `.env` | Jetson 上で実在する IF 名 |
| bridge | `.env` | bridge ホスト上で実在する IF 名 |
| visualization-host | `.env` | 可視化 PC 上で実在する IF 名 |

### jetson

```bash
cp .env.example .env
make sync-configs TARGET=jetson
make build TARGET=jetson
make up TARGET=jetson
make shell TARGET=jetson
```

### bridge

```bash
cp .env.example .env
# Linux bridge ホストで実在する IF 名を確認して .env の NETWORK_INTERFACE を更新
# 例: ip link show
# 例: ifconfig
make sync-configs TARGET=bridge
make build TARGET=bridge
make up TARGET=bridge
make shell TARGET=bridge
```

`NETWORK_INTERFACE` は bridge コンテナではなく、`network_mode: host` で共有される Linux ホスト側の IF 名に合わせてください。
`eno1` / `eth0` / `enp*` など名称は環境依存です。

### visualization-host

可視化PCには ROS 2 Humbleをネイティブに導入します。

[公式ドキュメント](https://docs.ros.org/en/humble/Installation/Ubuntu-Install-Debs.html)にしたがってROSをインストールします。

次に、ビルドに必要なシステムパッケージと ROS パッケージをまとめてインストールします。
パッケージ一覧は `configs/deps/packages.txt` で全ターゲット共通に管理しています。

```bash
make host-deps-install
```

### 共通

初回のみ Livox SDK2 をインストールします。

```bash
make livox-sdk-install
```

## 5. パッケージビルド

`make target-build` は `src/ros` 配下の ROS パッケージと `src/zenoh` / `src/zenoh-plugin-ros2dds` の Rust ワークスペースをビルドします。
`jetson` / `bridge` は通常コンテナ内で実行し、`visualization-host` はホスト環境で実行します。
ビルドコマンド (`colcon-build` / `zenoh-build` / `target-build`) は TARGET に依存しません。

```bash
make shell TARGET=<target>         # target: jetson / bridge / visualization-host
make target-build
```

<details><summary>補足: 個別ビルド</summary>

- `make target-build` は、`make colcon-build` と `make zenoh-build` を一度に行います。
- `make colcon-build` は、`src/ros` 配下の ROS パッケージを再帰的に探索してビルドします。`bridge` や `visualization-host` では ROS パッケージが無いため no-op です。
- `make zenoh-build` は、`src/zenoh` と `src/zenoh-plugin-ros2dds` の Rust ワークスペースを `cargo build --release` します。

</details>

## 7. 起動順

### 7.1 中継PC: bridge コンテナ内で zenoh router 起動

```bash
make shell TARGET=bridge
src/zenoh/target/release/zenohd -c configs/zenoh/zenoh-config-router.json
```

### 7.2 Jetson: zenoh client 起動

```bash
src/zenoh/target/release/zenohd -c configs/zenoh/zenoh-config-client.json
```

### 7.3 Jetson: Livoxドライバ起動

```bash
ros2 launch livox_ros_driver2 msg_MID360_launch.py
```

### 7.4 Jetson: FAST-LIO 起動

```bash
ros2 launch fast_lio mapping.launch.py config_file:=mid360.yaml rviz:=false
```

### 7.5 可視化PCホスト: トピック確認後に RViz2 起動

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

## 8. 環境変数と設定ファイル

全変数は `.env` の 1 ファイルで管理します。
`make sync-configs TARGET=<target>` を実行すると、`configs/` 配下のテンプレートに変数が展開されます。
ただし、`configs/fast_lio/mid360.yaml` は変数展開なしの共有設定ファイルとしてそのままコピーされます。

### 8.1 変数の反映先一覧

| 変数 | 反映先 | 用途 |
|---|---|---|
| `ZENOH_ROUTER_IP` | `configs/zenoh/zenoh-config-client.json` | zenoh client の接続先 IP |
| `ZENOH_ROUTER_PORT` | `configs/zenoh/zenoh-config-client.json`, `configs/zenoh/zenoh-config-router.json` | zenoh の待受/接続ポート |
| `NETWORK_INTERFACE` | `src/ros/unitree_ros2/setup.sh` | CycloneDDS の `NetworkInterface name` |
| `LIDAR_HOST_IP` | `src/ros/livox_ros_driver2/config/MID360_config.json` | LiDAR からのデータ受信先（ホスト側） |
| `LIDAR_DEVICE_IP` | `src/ros/livox_ros_driver2/config/MID360_config.json` | LiDAR 本体の IP |
| `RMW_IMPLEMENTATION` | `src/ros/unitree_ros2/setup.sh`, `docker-compose.yml` | ROS 2 ミドルウェア実装 |
| `ROS_DOMAIN_ID` | `docker-compose.yml` | ROS 2 ドメイン ID |
| `DOCKER_SHM_SIZE` | `docker-compose.yml` | Jetson コンテナの共有メモリサイズ |
| `LIDAR_DATASET_PATH` | `docker-compose.yml` | Jetson コンテナにマウントするデータパス |

### 8.2 sync-configs の展開対象

`src/` 配下の反映先は直接編集せず、必ず `configs/` 側を編集してから同期します。
`TARGET` は env ファイルの選択には使わず、同期先の選択にだけ使います。`configs/fast_lio/mid360.yaml` は Jetson で使う FAST_LIO 設定を target 非依存の共通ファイルとして同期します。

| テンプレート | 展開先 | 使用する変数 |
|---|---|---|
| `configs/livox/MID360_config.json` | `src/ros/livox_ros_driver2/config/MID360_config.json` | `LIDAR_HOST_IP`, `LIDAR_DEVICE_IP` |
| `configs/fast_lio/mid360.yaml` | `src/ros/FAST_LIO/config/mid360.yaml` | なし |
| `configs/unitree_ros2/setup.sh` | `src/ros/unitree_ros2/setup.sh` | `NETWORK_INTERFACE`, `RMW_IMPLEMENTATION` |
| `configs/zenoh/zenoh-config-client.json.tmpl` | `configs/zenoh/zenoh-config-client.json` | `ZENOH_ROUTER_IP`, `ZENOH_ROUTER_PORT` |
| `configs/zenoh/zenoh-config-router.json.tmpl` | `configs/zenoh/zenoh-config-router.json` | `ZENOH_ROUTER_PORT` |

```bash
make sync-configs TARGET=<target>
```

### 8.3 docker-compose.yml への反映

`docker-compose.yml` は `env_file` ディレクティブで `.env` を直接読み込みます。
`RMW_IMPLEMENTATION`, `ROS_DOMAIN_ID`, `DOCKER_SHM_SIZE`, `LIDAR_DATASET_PATH` はコンテナの環境変数・設定として注入されます。

- `ROS_LOCALHOST_ONLY=1` は bridge コンテナのみ `docker-compose.yml` にハードコードされています（Jetson 側では設定しません）。

### 8.4 zenoh 設定ファイル

- Jetson(client): `configs/zenoh/zenoh-config-client.json`
  - `connect.endpoints`: `tcp/${ZENOH_ROUTER_IP}:${ZENOH_ROUTER_PORT}`
  - `plugins.ros2dds.ros_localhost_only`: `false`

- 中継PC(router): `configs/zenoh/zenoh-config-router.json`
  - `listen.endpoints`: `tcp/0.0.0.0:${ZENOH_ROUTER_PORT}`
  - `plugins.ros2dds.ros_localhost_only`: `true`

## 9. 構成を変更した場合

`.env` を編集してから `make sync-configs TARGET=<target>` を再実行してください。

### 9.1 ビルド対象

ROS パッケージは `src/ros` 配下を、Rust ワークスペースは `src/zenoh` / `src/zenoh-plugin-ros2dds` を直接ビルドします。

`make colcon-build` / `make zenoh-build` / `make target-build` は Docker を使わない `visualization-host` でも利用できます。
将来 Docker ターゲットを増やす場合は `docker-compose.yml` にサービスとプロファイルを追加し、`Makefile` の `DOCKER_TARGETS` に名前を追加します。

## 10. Jetson への SSH 接続 (zellij)

Jetson での作業は複数ターミナルが必要です。zellij レイアウトを使って一発で4分割 SSH 接続を開けます。

### 10.1 初回セットアップ

SSH 公開鍵を Jetson に登録します（パスワード入力は1回だけ）。

```bash
ssh-copy-id go2
```

### 10.2 使い方

zellij 内で以下を実行すると、4分割の新しいタブが開き、各ペインが `ssh go2` で接続されます。

```bash
go2ssh
```

このエイリアスは `~/.zshrc` で定義されており、内部では以下を実行しています。

```bash
zellij action new-tab --layout go2
```

レイアウト定義: `~/.config/zellij/layouts/go2.kdl`

### 10.3 SSH 設定

`~/.ssh/config` に SSH multiplexing が設定されています。2本目以降の SSH 接続は既存の接続を再利用するため高速です。

## 11. トラブルシュート

### zenoh router が `does not match an available interface` で落ちる

次のようなログ:

```text
eno1: does not match an available interface
Failed to create RosDiscoveryInfoMgr
Error creating DDS Reader on ros_discovery_info: Precondition Not Met
```

これは `zenohd` 自体の listen 設定ではなく、CycloneDDS が `NETWORK_INTERFACE` に指定された IF 名を見つけられないときに起きます。

確認手順:

```bash
# bridge を動かす Linux ホストで確認
ip link show
# または
ifconfig
```

`.env` の `NETWORK_INTERFACE` を、実在する IF 名に合わせて修正してください。
修正後は設定を再生成します。

```bash
make sync-configs TARGET=bridge
```

その後、`src/ros/unitree_ros2/setup.sh` 内の `NetworkInterface name="..."` が期待どおりか確認してから、bridge コンテナ内で `zenohd` を再起動してください。

- `ros2 topic list` が空:
  - Jetson / bridge / 可視化PCホストの `ROS_DOMAIN_ID` 不一致を確認
  - `printenv RMW_IMPLEMENTATION ROS_LOCALHOST_ONLY ROS_DOMAIN_ID` を実行し、Jetson は `ROS_LOCALHOST_ONLY` が未設定、bridge と可視化PCホストは `1` になっていることを確認
  - `zenohd` 起動ログで接続断を確認

- `/livox/lidar` が出ない:
  - `MID360_config.json` の IP/Port を実機ネットワークに合わせる
  - LiDARとJetsonのL2疎通を確認

- RVizで点群が出ない:
  - Fixed Frame を `camera_init` に設定
  - `/cloud_registered` の QoS を確認

- `unitree_ros2`トピックが見えない:
  - Jetson コンテナで `ROS_LOCALHOST_ONLY` を設定していないことを確認
  - `ros2 daemon stop`を実行してキャッシュを削除する

- zenoh越しにトピックが見えない:
  - 可視化PCホストで `ros2 topic list` に現れるのは、その時点で publisher / subscriber の実体が存在して、zenoh の route が成立している topic
  - `unitree_ros2` の topic は特殊で、ロボットから直接 DDS が送られており publisher はないので、可視化PCホストで subscriber を作らないと現れない

- `make livox-sdk-install`がエラーになる
  - `src/Livox-SDK2/build`を削除する

# MEMO

/livox/lidarをrviz表示
ros2 launch livox_ros_driver2 rviz_MID360_launch.py
❯ rvizで/livox/lidarのディスプレイを設定できたが、fixed frameにmapしか表示されない

● Fixed Frame のドロップダウンは TF ツリー（/tf, /tf_static）に存在するフレームのみ表示します。Livox
   ドライバは点群ヘッダーに frame_id: livox_frame を設定しますが、TF に livox_frame フレームを
  publish していないため、ドロップダウンには出ません。

  解決方法: Fixed Frame の入力欄にドロップダウンから選ぶのではなく、直接 livox_frame
  と手入力してください。

  TF に存在しなくても、点群の frame_id と Fixed Frame が一致すれば点群は表示されます。

ros2 launch livox_ros_driver2 msg_MID360_launch.pyとすることで、fast-lioに点群を渡す。
ros2 topic echoやrvizで生点群を見ることはできなくなる。
fast-lioの出力の点群である/cloud-registeredはかなりsparceで、原因を調査中。

## 12. 設計判断: SLAM の実行場所

Jetson に画面がないため RViz2 は Desktop で実行する。では SLAM（FAST-LIO）はどちらで実行すべきか？

### 選択肢

| | A: Jetson で SLAM（現状） | B: Desktop で SLAM |
|---|---|---|
| ネットワーク通信量 | 小（~0.5-1 MB/s） | 大（~3-7 MB/s） |
| 送るデータ | `/cloud_registered`, `/Odometry`, `/path`, TF | `/livox/lidar`（生点群）, `/livox/imu`（高頻度） |
| 計算負荷の場所 | Jetson | Desktop |

### 結論: Jetson で SLAM を実行（現状維持）

- **通信量が 5-10 倍違う**: 生点群（MID360: ~20,000点/スキャン × 10Hz × 16-32bytes/点）を Zenoh 越しに流すのはボトルネックになりやすい。WiFi 環境では遅延・パケットロスのリスクが高い
- **FAST-LIO は軽量設計**: 組み込み向けに最適化されており Jetson で十分動作する
- **リアルタイム性**: SLAM をセンサーに近い場所で処理することで TF やオドメトリの遅延が最小化される。SLAM の遅延はナビゲーションに直接影響する
- **ネットワーク障害耐性**: 通信が途切れても Jetson 側で SLAM は継続動作し PCD 保存もできる
