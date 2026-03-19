# Go2 + MID360 + FAST-LIO(ROS2) + RViz(Host GUI)

このリポジトリは、Unitree Go2 (Jetson) 上で FAST-LIO(ROS2) を実行し、
VPN/インターネット越しに別PC(Ubuntu)のホスト環境で RViz2 を可視化するための手順をまとめています。

参照:
- https://techshare.co.jp/faq/unitree/mid360_slam_fast-lio.html
- https://github.com/eclipse-zenoh/zenoh-plugin-ros2dds

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
初回セットアップ時は、`configs/` 配下の正本を `src/` 配下へ反映するために `make sync-configs` を先に実行します。

### jetson
```bash
make sync-configs
make build TARGET=jetson
make up TARGET=jetson
make shell TARGET=jetson
```

コンテナ起動後、初回のみコンテナ内で Livox SDK2 をインストールします。

```bash
make shell TARGET=jetson
make livox-sdk-install
```

### bridge
```bash
make sync-configs
make build TARGET=bridge
make up TARGET=bridge
make shell TARGET=bridge
```

### visualization-host

可視化PCには ROS 2 Humbleをネイティブに導入します。

[公式ドキュメント](https://docs.ros.org/en/humble/Installation/Ubuntu-Install-Debs.html)にしたがってROSをインストールします。

次に、ビルドに必要なシステムパッケージと ROS パッケージをまとめてインストールします。
パッケージ一覧は `configs/deps/packages.txt` で全ターゲット共通に管理しています。

```bash
make host-deps-install
```

[公式ドキュメント](https://github.com/Livox-SDK/Livox-SDK2)に従って Livox SDK2 をインストールします。
`vcs import` 後は `src/Livox-SDK2` が存在するため、そこからビルド・インストールします。

```bash
make livox-sdk-install
```

## 5. パッケージビルド

`make target-build` は `src/ros` 配下の ROS パッケージと `src/zenoh` / `src/zenoh-plugin-ros2dds` の Rust ワークスペースをビルドします。
`jetson` / `bridge` は通常コンテナ内で実行し、`visualization-host` はホスト環境で実行します。
ビルドコマンド (`colcon-build` / `zenoh-build` / `target-build`) は TARGET に依存しません。

```bash
make shell TARGET=<target>         # target: jetson / bridge TODO: visualization-hostで環境変数セットやsourceを行う
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
src/zenoh/target/release/zenohd -c zenoh-config-router.json
```

### 7.2 Jetson: zenoh client 起動

```bash
src/zenoh/target/release/zenohd -c zenoh-config-client.json
```

### 7.3 Jetson: Livoxドライバ起動

```bash
ros2 launch livox_ros_driver2 msg_MID360_launch.py
```

### 7.4 Jetson: FAST-LIO(ROS2) 起動 (Go2側でRVizは起動しない)

```bash
ros2 launch fast_lio mapping.launch.py config_file:=mid360.yaml rviz:=false
```

### 7.5 可視化PCホスト: トピック確認後に RViz2 起動

```bash
source /opt/ros/humble/setup.bash
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export ROS_DOMAIN_ID=0
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

## 8. zenoh 設定ファイル

- Jetson(client): `zenoh-config-client.json`
  - `connect.endpoints`: `tcp/135.149.56.251:7447`
  - `plugins.ros2dds.domain`: `0`
  - `plugins.ros2dds.ros_localhost_only`: `false`

- 中継PC(router): `zenoh-config-router.json`
  - `listen.endpoints`: `tcp/0.0.0.0:7447`
  - `plugins.ros2dds.domain`: `0`
  - `plugins.ros2dds.ros_localhost_only`: `true`

## 9. 構成を変更した場合

`make sync-configs` は初回セットアップではコンテナ作成前に実行します。
それ以降は、`configs/` 配下の設定を変更したときだけ再実行してください。
`src/` 配下の反映先は直接編集せず、必ず `configs/` 側を編集してから同期します。

- `configs/livox/MID360_config.json`
  - 反映先: `src/ros/livox_ros_driver2/config/MID360_config.json`
  - 変更対象: LiDAR の IP/Port

- `configs/unitree_ros2/setup.sh`
  - 反映先: `src/ros/unitree_ros2/setup.sh`
  - 変更対象: `source /opt/ros/humble/setup.bash` と `CYCLONEDDS_URI` 内の `NetworkInterface name`

```bash
make sync-configs
```

### 9.1 ビルド対象

ROS パッケージは `src/ros` 配下を、Rust ワークスペースは `src/zenoh` / `src/zenoh-plugin-ros2dds` を直接ビルドします。

`make colcon-build` / `make zenoh-build` / `make target-build` は Docker を使わない `visualization-host` でも利用できます。
将来 Docker ターゲットを増やす場合は `docker-compose.yml` にサービスとプロファイルを追加し、`Makefile` の `DOCKER_TARGETS` に名前を追加します。

### 9.2 環境変数メモ（調査中）

この節の内容は現行構成の調査メモです。運用ルールとして確定していないため、必要に応じて実機設定と `docker/docker-compose.yml` を再確認してください。

- `make up TARGET=<target>` で起動するコンテナには `docker/docker-compose.yml` から環境変数が注入されます。
- `RMW_IMPLEMENTATION=rmw_cyclonedds_cpp` は Jetson / bridge の両方で設定されています。
- `ROS_DOMAIN_ID` は Jetson / bridge / 可視化PCホストで同じ値を使います。変更したい場合は `.env` を作るか、起動時に一時上書きします。
- `ROS_LOCALHOST_ONLY=1` は bridge と可視化PCホストで設定し、Jetson 側では設定しません。

```bash
cp .env.example .env
# 必要なら ROS_DOMAIN_ID を変更
```

```bash
ROS_DOMAIN_ID=5 make up TARGET=jetson
ROS_DOMAIN_ID=5 make up TARGET=bridge
```

現在の値はコンテナ内、またはホストシェルで確認できます。

```bash
printenv RMW_IMPLEMENTATION ROS_LOCALHOST_ONLY ROS_DOMAIN_ID
```

## 10. トラブルシュート

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
