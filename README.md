# Go2 + MID360 + FAST-LIO(ROS2) + RViz(遠隔PC)

このリポジトリは、Unitree Go2 (Jetson) 上で FAST-LIO(ROS2) を実行し、
VPN/インターネット越しに別PC(Ubuntu)の RViz2 で可視化するための手順をまとめています。

参照:
- https://techshare.co.jp/faq/unitree/mid360_slam_fast-lio.html
- https://github.com/eclipse-zenoh/zenoh-plugin-ros2dds

## 1. 構成

- SLAM実行: Go2 Jetson (`jetson` コンテナ)
- 可視化: Ubuntu PC (`rviz2`)
- 中継: zenoh (`zenohd + ros2dds plugin`)

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

## 4. コンテナ作成
ROS環境を含めすべてコンテナ上で実行します。
デプロイ先ごとに `TARGET` を切り替えます。
初回セットアップ時は、`configs/` 配下の正本を `src/` 配下へ反映するために `make sync-configs` を先に実行します。

```bash
# Jetson 向け (jetson)
make sync-configs
make build TARGET=jetson
make up TARGET=jetson
make shell TARGET=jetson

# 可視化PC向け (desktop)
make sync-configs
make build TARGET=desktop
make up TARGET=desktop
make shell TARGET=desktop
```

`make shell TARGET=<target>` で入ると、以下を自動で読み込みます。
- `/workspace/src/ros/unitree_ros2/setup.sh`
- `/workspace/install/setup.bash`

起動時に、実際に `source` できたパスを `[auto-source] sourced: ...` として表示します。
未生成のファイルは `[auto-source] missing: ...` と表示されます。

`src` 配下のデプロイ対象は以下のファイルで管理します。
- 共通: `configs/deploy/src-common.txt`
- Jetson固有差分: `configs/deploy/src-jetson.txt`
- Desktop PC固有差分: `configs/deploy/src-desktop.txt`

### (Optional) 確認/ステージング:

```bash
cd /home/unitree/go2-lab
make src-list TARGET=jetson
make src-stage TARGET=jetson STAGE_DIR=.staging/jetson
```

`make src-list TARGET=<target>` は `common + target固有差分` の合成結果を表示します。
将来ターゲットを増やす場合は `configs/deploy/src-<new-target>.txt` を追加します。
（Docker コンテナ実行が必要なら `Makefile` に `PROFILE/SERVICES` の対応を追加）
列挙したパスがリポジトリ内に存在しない場合、`make src-list` / `make colcon-build` / `make target-build` は設定エラーとして即座に失敗します。

## 5. パッケージビルド

コンテナ作成後、`src/ros` 配下の ROS パッケージと、`src/zenoh` / `src/zenoh-plugin-ros2dds` の Rust ワークスペースをビルドします。
`make sync-configs` はコンテナ作成前に一度実行すれば十分で、ビルドのたびに毎回実行する必要はありません。

```bash
make shell TARGET=<target>         # target: jetson / desktop
make target-build TARGET=<target>
```

<details><summary>補足: 個別ビルド</summary>

- `make target-build TARGET=<target>` は、`make colcon-build`と`make zenoh-build`を一度に行います。
- `make colcon-build TARGET=<target>` は、対象ターゲットのうち `src/ros` 配下にある search root を `colcon build --base-paths` に渡し、その配下の ROS パッケージを再帰的に探索してビルドします。
- `make zenoh-build TARGET=<target>` は、`src/zenoh` と `src/zenoh-plugin-ros2dds` の Rust ワークスペースを `cargo build --release` します。

## 6. 環境変数 (Jetson/可視化PC 共通)

`make up TARGET=<target>` で起動するコンテナには、以下の ROS 環境変数を `docker/docker-compose.yml` から自動で注入します。
`make shell TARGET=<target>` で入ったシェルでも、そのまま有効です。

```bash
RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
ROS_LOCALHOST_ONLY=1
ROS_DOMAIN_ID=0
```

- `ROS_DOMAIN_ID` は Jetson と可視化PCで必ず同じ値にします。
- DDSループ防止のため、`ROS_LOCALHOST_ONLY=1` を使います。
- 毎ターミナルで `export` する必要はありません。

`ROS_DOMAIN_ID` を変更したい場合は、リポジトリ直下で `.env` を作るか、起動時に一時上書きします。

```bash
cp .env.example .env
# 必要なら ROS_DOMAIN_ID を変更
```

```bash
ROS_DOMAIN_ID=5 make up TARGET=jetson
ROS_DOMAIN_ID=5 make up TARGET=desktop
```

現在の値はコンテナ内で確認できます。

```bash
printenv RMW_IMPLEMENTATION ROS_LOCALHOST_ONLY ROS_DOMAIN_ID
```

## 7. 起動順

### 7.1 可視化PC: zenoh router 起動

```bash
src/zenoh/target/release/zenohd -c zenoh-config-azure.json
```

### 7.2 Jetson: zenoh client 起動

```bash
src/zenoh/target/release/zenohd -c zenoh-config-jetson.json
```

### 7.3 Jetson: Livoxドライバ起動

```bash
ros2 launch livox_ros_driver2 msg_MID360_launch.py
```

### 7.4 Jetson: FAST-LIO(ROS2) 起動 (Go2側でRVizは起動しない)

別ターミナルでも `make shell TARGET=jetson` で同じ環境を読み込み:

```bash
ros2 launch fast_lio mapping.launch.py config_file:=mid360.yaml rviz:=false
```

### 7.6 可視化PC: トピック確認後に RViz2 起動

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

## 8. 疎通/動作確認

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

## 9. zenoh 設定ファイル

- Jetson(client): `zenoh-config-jetson.json`
  - `connect.endpoints`: `tcp/135.149.56.251:7447`
  - `plugins.ros2dds.domain`: `0`
  - `plugins.ros2dds.ros_localhost_only`: `true`

- 可視化PC(router): `zenoh-config-azure.json`
  - `listen.endpoints`: `tcp/0.0.0.0:7447`
  - `plugins.ros2dds.domain`: `0`
  - `plugins.ros2dds.ros_localhost_only`: `true`

## 10. 構成を変更した場合

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

## 11. トラブルシュート

- `ros2 topic list` が空:
  - Jetson/可視化PCの `ROS_DOMAIN_ID` 不一致を確認
  - コンテナ内で `printenv RMW_IMPLEMENTATION ROS_LOCALHOST_ONLY ROS_DOMAIN_ID` を実行し、両端で同じ値が有効か確認
  - `zenohd` 起動ログで接続断を確認

- `/livox/lidar` が出ない:
  - `MID360_config.json` の IP/Port を実機ネットワークに合わせる
  - LiDARとJetsonのL2疎通を確認

- RVizで点群が出ない:
  - Fixed Frame を `camera_init` に設定
  - `/cloud_registered` の QoS を確認

- `unitree_ros2`トピックが見えない:
  - `ros2 daemon stop`を実行してキャッシュを削除する
