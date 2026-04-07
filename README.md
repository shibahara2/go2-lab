# Go2 + MID360 + FAST-LIO(ROS2)

このリポジトリは、Ubuntu 22 の `desktop` マシンを標準の実行環境として、Go2 / MID360 / FAST-LIO の開発手順をまとめたものです。
標準モードは `.env` の `DISTRIBUTED_MODE=0` で、zenoh を前提にしません。

`DISTRIBUTED_MODE=1` にすると、将来的には次の 3 ノード分散構成を使う前提です。

- `jetson`: zenoh client
- `desktop`: zenoh client
- `server`: zenoh router

参照:

- <https://techshare.co.jp/faq/unitree/mid360_slam_fast-lio.html>
- <https://github.com/eclipse-zenoh/zenoh-plugin-ros2dds>

## 1. 構成

標準構成は `desktop` 単独運用です。
Go2 実機が出す topic を Jetson から `desktop` へ中継したいときだけ、分散構成を使います。

このリポジトリで Docker 管理している Linux ターゲットは 2 つです。

| 実際の役割 | リポジトリ内の `TARGET` | 実行場所 |
|---|---|---|
| Go2 Jetson container | `jetson` | Jetson / docking station |
| Ubuntu desktop PC container (`desktop`) | `bridge` | Ubuntu desktop PC |

`TARGET=bridge` は Makefile / docker-compose 上の名前で、この README では `desktop` と呼びます。
分散モード用の `server` は後で詳細化する予定で、今回は標準運用に含めません。

## 2. clone

```bash
git clone <this-repo-url>
cd go2-lab
```

標準モードでは `desktop` 用 clone だけで構いません。
分散モードを使う場合は Jetson 用 clone も別途用意してください。

## 3. 外部リポジトリ取得

依存のうち upstream 追従を続けるものだけを `go2.repos` で管理しています。
現状 `vcstool` で取得する対象は `zenoh` と `zenoh-plugin-ros2dds` の 2 件です。これらは分散モード用です。

次の依存は vendor 化しており、`go2-lab` の git で直接追跡します。

- `src/Livox-SDK2`
- `src/ros/FAST_LIO`
- `src/ros/livox_ros_driver2`
- `src/ros/unitree_ros2`

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

### 3.4 ローカル変更の扱い

vendor 化した依存は `go2-lab` の変更としてそのまま編集・commit します。  
`go2.repos` で取得する `zenoh` 系 2 リポジトリは upstream pin 管理のままとし、通常運用ではローカル変更を持たない前提です。

将来 `zenoh` 系にも継続的な変更が必要になった場合は、patch 運用を再導入せず、そのリポジトリ単位で `fork + pin` に切り替える方針です。

## 4. 実行環境構築

各 Linux マシンで `.env.example` を `.env` にコピーして編集します。  
標準モードでは `desktop` マシン上の `.env` だけ設定すれば動きます。

```bash
cp .env.example .env
```

`make sync-configs TARGET=<target>` は、その clone が動いているマシンの `.env` を使って設定ファイルを展開します。

### 4.1 desktop container (`TARGET=bridge`)

まずは `DISTRIBUTED_MODE=0` のまま、desktop 側で以下をその Ubuntu 22 環境に合わせます。

- `NETWORK_INTERFACE`: Ubuntu desktop PC 上で実在する IF 名
- `LIDAR_HOST_IP`, `LIDAR_DEVICE_IP`: MID360 実配線に合わせた IP
- `ROS_DOMAIN_ID`, `RMW_IMPLEMENTATION`: この clone で使う ROS 2 設定

```bash
cp .env.example .env
make sync-configs TARGET=bridge
make build TARGET=bridge
make up TARGET=bridge
make shell TARGET=bridge
```

`network_mode: host` を使っているため、`NETWORK_INTERFACE` はコンテナ内の仮想 IF ではなく Linux ホスト側の IF 名に合わせてください。

確認例:

```bash
ip link show
# または
ifconfig
```

### 4.2 分散モード (`DISTRIBUTED_MODE=1`)

分散モードでは `jetson`, `desktop`, `server` の 3 ノード構成を使います。
この詳細手順は後で追記します。現時点では `DISTRIBUTED_MODE=0` を標準運用としてください。

### 4.3 共通

初回のみ Livox SDK2 をインストールします。

```bash
make livox-sdk-install
```

## 5. パッケージビルド

`make target-build` は標準モードでは `src/ros` 配下の ROS パッケージだけをビルドします。
`DISTRIBUTED_MODE=1` のときだけ `src/zenoh` / `src/zenoh-plugin-ros2dds` もビルド対象に含めます。

- `TARGET=bridge`: Ubuntu desktop PC コンテナ内で実行
- `TARGET=jetson`: 分散モード時に Jetson コンテナ内で実行

```bash
make shell TARGET=<target>   # target: jetson / bridge
make target-build
```

補足:

- `make target-build` は常に `make colcon-build` を実行します。
- `make target-build` は `DISTRIBUTED_MODE=1` のときだけ `make zenoh-build` を追加で実行します。
- `make colcon-build` は `src/ros` 配下の ROS パッケージをビルドします。
- `make zenoh-build` は分散モード専用で、`src/zenoh` と `src/zenoh-plugin-ros2dds` を `cargo build --release` します。

## 6. 起動順

### 6.1 desktop: 開発コンテナに入る

```bash
make shell TARGET=bridge
```

### 6.2 desktop: Livox ドライバ起動

```bash
ros2 launch livox_ros_driver2 msg_MID360_launch.py
```

### 6.3 desktop: FAST-LIO 起動

```bash
ros2 launch fast_lio mapping.launch.py config_file:=mid360.yaml rviz:=false
```

### 6.4 desktop: topic 確認と RViz2

```bash
ros2 topic list
ros2 topic echo /Odometry --once
rviz2
```

RViz の目安:

- Fixed Frame: `camera_init`
- 表示候補:
  - `/cloud_registered`
  - `/Odometry`
  - `/tf`
  - `/tf_static`

### 6.5 分散モードの zenoh 起動

`make zenoh-client` は `DISTRIBUTED_MODE=1` のときだけ利用できます。
`DISTRIBUTED_MODE=0` では実行できません。

### 6.6 Go2 IMU publisher 起動

Go2 の `/lowstate` を ROS 標準の `sensor_msgs/msg/Imu` に変換して `/go2/imu` へ配信します。

```bash
make shell TARGET=<target>   # target: jetson / bridge
make colcon-build
source install/setup.bash
ros2 run imu_publisher imu_publisher
```

確認例:

```bash
ros2 topic echo /go2/imu --once
```

## 7. 環境変数と設定ファイル

各 clone の `.env` から設定を生成します。  
`configs/fast_lio/mid360.yaml` は変数展開なしでそのまま同期されます。

### 7.1 主要変数

| 変数 | 反映先 | 用途 |
|---|---|---|
| `DISTRIBUTED_MODE` | `Makefile`, `scripts/run_zenoh_client.sh`, `scripts/sync_configs.sh` | `0` は desktop 単独、`1` は分散モード |
| `ZENOH_ROUTER_IP` | `configs/zenoh/zenoh-config-client.json` | 分散モード時の zenoh router 接続先 IP |
| `ZENOH_ROUTER_PORT` | `configs/zenoh/zenoh-config-client.json`, `configs/zenoh/zenoh-config-router.json` | 分散モード時の zenoh 接続ポート |
| `ZENOH_CONFIG_OVERRIDE` | `make zenoh-client` 実行時の環境変数 | 分散モード時の zenoh transport override |
| `NETWORK_INTERFACE` | `src/ros/unitree_ros2/setup.sh` | CycloneDDS の `NetworkInterface name` |
| `LIDAR_HOST_IP` | `src/ros/livox_ros_driver2/config/MID360_config.json` | LiDAR 受信先 IP |
| `LIDAR_DEVICE_IP` | `src/ros/livox_ros_driver2/config/MID360_config.json` | LiDAR 本体 IP |
| `RMW_IMPLEMENTATION` | `src/ros/unitree_ros2/setup.sh`, `docker/docker-compose.yml` | ROS 2 ミドルウェア実装 |
| `ROS_DOMAIN_ID` | `docker/docker-compose.yml` | ROS 2 ドメイン ID |
| `DOCKER_SHM_SIZE` | `docker/docker-compose.yml` | Docker 共有メモリサイズ |
| `LIDAR_DATASET_PATH` | `docker/docker-compose.yml` | Jetson コンテナにマウントする任意データパス |

### 7.2 `sync-configs` の展開対象

次のファイルは `configs/` から生成・同期するため、展開先ではなく `configs/` 側を編集してから再同期してください。

| テンプレート | 展開先 | 使用する変数 |
|---|---|---|
| `configs/livox/MID360_config.json` | `src/ros/livox_ros_driver2/config/MID360_config.json` | `LIDAR_HOST_IP`, `LIDAR_DEVICE_IP` |
| `configs/fast_lio/mid360.yaml` | `src/ros/FAST_LIO/config/mid360.yaml` | なし |
| `configs/unitree_ros2/setup.sh` | `src/ros/unitree_ros2/setup.sh` | `NETWORK_INTERFACE`, `RMW_IMPLEMENTATION` |
| `configs/zenoh/zenoh-config-client.json.tmpl` | `configs/zenoh/zenoh-config-client.json` | `DISTRIBUTED_MODE=1` のときだけ `ZENOH_ROUTER_IP`, `ZENOH_ROUTER_PORT` |
| `configs/zenoh/zenoh-config-router.json.tmpl` | `configs/zenoh/zenoh-config-router.json` | `ZENOH_ROUTER_PORT` |

```bash
make sync-configs TARGET=<target>
```

### 7.3 zenoh client 設定

- Jetson / desktop client: `configs/zenoh/zenoh-config-client.json`
  - `mode: "client"`
  - `connect.endpoints: ["tcp/${ZENOH_ROUTER_IP}:${ZENOH_ROUTER_PORT}"]`
  - `plugins.ros2dds.ros_localhost_only: false`

`make zenoh-client` は `DISTRIBUTED_MODE=1` のときだけ利用できます。
`.env` を読み込み、`ZENOH_CONFIG_OVERRIDE` が設定されていればその値を付けた状態で `zenohd -c configs/zenoh/zenoh-config-client.json` を起動します。

巨大な `PointCloud2` が congestion で drop される疑いがあるときは、`.env` に次を入れてから `make zenoh-client` を起動してください。

```bash
ZENOH_CONFIG_OVERRIDE=transport/link/tx/queue/congestion_control/drop/wait_before_drop=1000000
```

`configs/zenoh/zenoh-config-router.json` は Linux 上で router を立てる場合のテンプレートです。  
`DISTRIBUTED_MODE=0` の標準運用では必須ではありません。

## 8. 構成を変更した場合

`.env` を編集したら、対象マシンで再度 `make sync-configs TARGET=<target>` を実行してください。

```bash
make sync-configs TARGET=bridge
```

## 9. Jetson への SSH 接続 (zellij)

Jetson での作業は複数ターミナルが必要です。zellij レイアウトを使うと一度に複数 SSH ペインを開けます。

### 9.1 初回セットアップ

```bash
ssh-copy-id go2
```

### 9.2 使い方

```bash
go2ssh
```

このエイリアスは `~/.zshrc` で `zellij action new-tab --layout go2` を呼び出す想定です。

### 9.3 SSH 設定

`~/.ssh/config` に SSH multiplexing を設定しておくと、2 本目以降の接続が高速になります。

## 10. トラブルシュート

### zenoh client 起動時に `does not match an available interface` で落ちる

例:

```text
eno1: does not match an available interface
Failed to create RosDiscoveryInfoMgr
Error creating DDS Reader on ros_discovery_info: Precondition Not Met
```

これは zenoh の接続先設定ではなく、CycloneDDS が `NETWORK_INTERFACE` に指定された IF 名を見つけられないときに起きます。

確認手順:

```bash
# Jetson または desktop 側の Linux ホストで確認
ip link show
# または
ifconfig
```

`.env` の `NETWORK_INTERFACE` を実在する IF 名に直し、設定を再生成してください。

```bash
make sync-configs TARGET=jetson
# または
make sync-configs TARGET=bridge
```

### `ros2 topic list` が空

- 単独運用では `NETWORK_INTERFACE` が正しいか確認する
- 分散運用では Jetson 側と desktop 側で `ROS_DOMAIN_ID` が一致しているか確認する
- 分散運用では両方の `.env` で `RMW_IMPLEMENTATION` が一致しているか確認する
- 分散運用では Jetson / desktop の両方で zenoh client が起動しているか確認する
- 分散運用では zenoh router に到達できるか確認する

### `/livox/lidar` が出ない

- `MID360_config.json` の IP 設定を実機ネットワークに合わせる
- LiDAR と Jetson の L2 疎通を確認する

### RViz で点群が出ない

- Fixed Frame を `camera_init` にする
- `/cloud_registered` が publish されているか確認する
- desktop container 側で `ros2 topic echo /Odometry --once` が通るか確認する
● Fixed Frame のドロップダウンは TF ツリー（/tf, /tf_static）に存在するフレームのみ表示します。Livox
   ドライバは点群ヘッダーに frame_id: livox_frame を設定しますが、TF に livox_frame フレームを
  publish していないため、ドロップダウンには出ません。

  解決方法: Fixed Frame の入力欄にドロップダウンから選ぶのではなく、直接 livox_frame
  と手入力してください。

  TF に存在しなくても、点群の frame_id と Fixed Frame が一致すれば点群は表示されます。

ros2 launch livox_ros_driver2 msg_MID360_launch.pyとすることで、fast-lioに点群を渡す。
ros2 topic echoやrvizで生点群を見ることはできなくなる。
fast-lioの出力の点群である/cloud-registeredはかなりsparceで、原因を調査中。

### `unitree_ros2` topic が見えない

- `src/ros/unitree_ros2/setup.sh` に反映された `NETWORK_INTERFACE` を確認する
- `ros2 daemon stop` を実行して discovery キャッシュを消してから再確認する

### zenoh 越しに topic が見えない

- `DISTRIBUTED_MODE=1` になっているか確認する
- `ZENOH_ROUTER_IP` が mac host の正しい IP を向いているか確認する
- mac host 側の firewall / port 開放状態を確認する
- Jetson / desktop の両方で `configs/zenoh/zenoh-config-client.json` が同じ router を向いているか確認する

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

### 主要トピックの計測結果

| トピック | 周波数 (Hz) | メッセージサイズ (MB) | 帯域 (Mbps) | 備考 |
|---|---|---|---|---|
| `/Laser_map` | ~1 | ~28.5–30.7 | ~240 | 累積地図。サイズは時間とともに増加 | FAST-LIO 出力 (地図)
| `/livox/lidar` | ~10 | ~0.52 | ~42 | MID360 生点群 |
| `/cloud_registered` | ~10 | ~0.22 | ~18 | FAST-LIO 出力（位置合わせ済み点群） |

<details><summary>計測生データ</summary>

- /Laser_mapについて
  ```
  $ ros2 topic hz /Laser_map
average rate: 0.999
        min: 1.000s max: 1.002s std dev: 0.00074s window: 2
average rate: 0.999
        min: 1.000s max: 1.002s std dev: 0.00061s window: 3
average rate: 0.998
        min: 1.000s max: 1.003s std dev: 0.00121s window: 4
average rate: 0.999
        min: 0.999s max: 1.003s std dev: 0.00157s window: 6
average rate: 0.999
        min: 0.999s max: 1.003s std dev: 0.00146s window: 7
average rate: 0.999
        min: 0.999s max: 1.003s std dev: 0.00138s window: 9
average rate: 0.999
        min: 0.999s max: 1.003s std dev: 0.00131s window: 10
average rate: 0.999
        min: 0.998s max: 1.003s std dev: 0.00148s window: 12
average rate: 0.999
        min: 0.997s max: 1.005s std dev: 0.00215s window: 14
average rate: 0.999
        min: 0.997s max: 1.005s std dev: 0.00208s window: 15
average rate: 0.999
        min: 0.997s max: 1.006s std dev: 0.00244s window: 17
average rate: 0.999
        min: 0.997s max: 1.006s std dev: 0.00245s window: 19
average rate: 0.999
        min: 0.997s max: 1.006s std dev: 0.00240s window: 20
average rate: 0.999
        min: 0.997s max: 1.006s std dev: 0.00249s window: 21
^C#
# root @ ubuntu in /workspace [11:38:15] C:2
$ ros2 topic bw /Laser_map
Subscribed to [/Laser_map]
57.04 MB/s from 2 messages
        Message size mean: 28.56 MB min: 28.45 MB max: 28.68 MB
28.59 MB/s from 2 messages
        Message size mean: 28.56 MB min: 28.45 MB max: 28.68 MB
19.06 MB/s from 2 messages
        Message size mean: 28.56 MB min: 28.45 MB max: 28.68 MB
21.60 MB/s from 3 messages
        Message size mean: 28.82 MB min: 28.45 MB max: 29.34 MB
17.30 MB/s from 3 messages
        Message size mean: 28.82 MB min: 28.45 MB max: 29.34 MB
24.27 MB/s from 5 messages
        Message size mean: 29.16 MB min: 28.45 MB max: 29.78 MB
25.10 MB/s from 6 messages
        Message size mean: 29.30 MB min: 28.45 MB max: 30.00 MB
25.73 MB/s from 7 messages
        Message size mean: 29.43 MB min: 28.45 MB max: 30.22 MB
26.25 MB/s from 8 messages
        Message size mean: 29.56 MB min: 28.45 MB max: 30.43 MB
26.69 MB/s from 9 messages
        Message size mean: 29.68 MB min: 28.45 MB max: 30.65 MB
  ```

- /livox/lidarについて
  ```
  $ ros2 topic hz /livox/lidar
average rate: 9.943
        min: 0.098s max: 0.104s std dev: 0.00183s window: 12
average rate: 9.980
        min: 0.097s max: 0.104s std dev: 0.00195s window: 23
average rate: 9.994
        min: 0.097s max: 0.104s std dev: 0.00190s window: 34
average rate: 9.990
        min: 0.096s max: 0.106s std dev: 0.00241s window: 45
average rate: 9.988
        min: 0.096s max: 0.106s std dev: 0.00233s window: 55
^C#
# root @ ubuntu in /workspace [11:41:47] C:2
$ ros2 topic bw /livox/lidar
Subscribed to [/livox/lidar]
5.65 MB/s from 10 messages
        Message size mean: 0.52 MB min: 0.52 MB max: 0.52 MB
5.42 MB/s from 20 messages
        Message size mean: 0.52 MB min: 0.52 MB max: 0.52 MB
5.34 MB/s from 30 messages
        Message size mean: 0.52 MB min: 0.52 MB max: 0.52 MB
5.31 MB/s from 40 messages
        Message size mean: 0.52 MB min: 0.52 MB max: 0.52 MB
5.29 MB/s from 50 messages
        Message size mean: 0.52 MB min: 0.52 MB max: 0.52 MB
  ```

- /cloud_registeredについて
  ```
  $ ros2 topic hz /cloud_registered
average rate: 9.986
        min: 0.018s max: 0.179s std dev: 0.04621s window: 11
average rate: 9.991
        min: 0.018s max: 0.180s std dev: 0.04402s window: 22
average rate: 10.055
        min: 0.009s max: 0.190s std dev: 0.04661s window: 33
average rate: 10.075
        min: 0.009s max: 0.190s std dev: 0.04288s window: 44
average rate: 10.061
        min: 0.009s max: 0.190s std dev: 0.04332s window: 54
average rate: 10.075
        min: 0.009s max: 0.191s std dev: 0.04808s window: 65
^C#
# root @ ubuntu in /workspace [11:43:11] C:2
$ ros2 topic bw /cloud_registered
Subscribed to [/cloud_registered]
2.40 MB/s from 10 messages
        Message size mean: 0.22 MB min: 0.22 MB max: 0.23 MB
2.32 MB/s from 20 messages
        Message size mean: 0.22 MB min: 0.22 MB max: 0.23 MB
2.29 MB/s from 30 messages
        Message size mean: 0.22 MB min: 0.22 MB max: 0.23 MB
2.21 MB/s from 39 messages
        Message size mean: 0.22 MB min: 0.22 MB max: 0.23 MB
2.25 MB/s from 50 messages
        Message size mean: 0.22 MB min: 0.21 MB max: 0.23 MB
  ```

</details>
