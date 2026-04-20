# ADR 0003: DGX Spark 向け専用コンテナと ML 依存の封じ込め

- Status: Accepted
- Date: 2026-04-19
- Related: ADR 0001 (voice_teleop), ADR 0002 (Python deps)

## Context

ADR 0001 で voice_teleop は Azure OpenAI Realtime API を使う構成で導入した。運用経験から以下が問題になった。

- 発話 → transcript 到達まで数百 ms のクラウド往復レイテンシが制御経路に乗る
- API キーとネットワーク接続が必須
- ハード更新で DGX Spark (arm64 Grace Blackwell + GPU) が使えるようになり、ローカル ASR に移行する余地ができた

ASR のローカル化には NVIDIA Parakeet (`nvidia/parakeet-tdt_ctc-0.6b-ja`) とノード内実装の energy-based VAD を使う。Parakeet の公式ランタイムは NeMo toolkit 上にあり、NeMo toolkit / torch+CUDA は apt パッケージが存在しない。ADR 0002 の「rclpy を pip / venv に持ち込まない」方針と直接ぶつかる。ADR 0002 は「apt に無い依存が要る場合は新 ADR を起票して決める」と規定しており、本 ADR がその再検討にあたる。

## Decision

voice_teleop のような重量 ML ノードは **プラットフォーム単位の専用 Docker イメージ内に閉じ込める**。ホスト側には pip / venv / uv を導入しない。

1. **compose profile の粒度**: platform / runtime 名で service / profile を切る。DGX Spark 上では `dgx-spark-humble` と `dgx-spark-jazzy` を分け、voice_teleop や将来の GPU ノードは Jazzy 側に寄せる。
2. **新規ファイル**: `docker/Dockerfile.dgx-spark-jazzy`, `docker/docker-compose.dgx-spark.yml`, `Makefile` の `dgx-spark-*` ターゲット。
3. **ベースイメージ**: `nvcr.io/nvidia/pytorch:*-py3` をベースにし、`pip install nemo_toolkit[asr]` で Parakeet ランタイムを構築する。NeMo コンテナは arm64 / Blackwell での適合性確認コストが高いため採用しない。
4. **ROS の重複**: `dgx-spark-jazzy` だけは Ubuntu 24.04 に合わせて ROS 2 Jazzy (`ros-jazzy-ros-base` + `rclpy` + `geometry_msgs`) を image 内に apt で導入する。ROS 2 apt source の追加は Jazzy/Noble の公式手順どおり **`universe` 有効化 + `ros2-apt-source`** を使う。DGX Spark 上のロボット互換 runtime は別途 `dgx-spark-humble` で持つ。
5. **Isaac ROS 対応**: `dgx-spark` image には NVIDIA Isaac ROS apt repository と rosdep definitions も追加し、将来 `ros-jazzy-isaac-*` 系パッケージを install できる基盤を先に用意する。ただし ROS 本体の配布元は引き続き ROS 公式 repository とし、Isaac ROS repo は追加配布元としてのみ扱う。`src/ros/unitree_ros2` upstream は Humble 想定のため、DGX Spark は `unitree_ros2` をネイティブ実行する基盤とは位置付けず、必要な連携は bridge/zenoh 経由の topic 利用で行う。
6. **ホスト側**: `make host-deps-install` は不変。DGX Spark では `make dgx-spark-build && make dgx-spark-up` で Humble/Jazzy runtime を上げ、ML 系は Jazzy 側に閉じ込める。ホストへの pip 汚染は起こさない。
7. **モデルキャッシュ**: HuggingFace / NeMo のモデルは `~/.cache/huggingface` を host bind mount して永続化する。初回 DL 後は再起動で再取得しない。
8. **package.xml**: pip 依存は rosdep キーが無いので `package.xml` には書かない。Dockerfile を source of truth とし、voice_teleop の `package.xml` にコメントで本 ADR と Dockerfile を参照させる。

## Alternatives considered

- **ホスト `pip install --user`**: apt 経由の rclpy と user site-packages の PATH が衝突する懸念。PEP 668 (Ubuntu 24.04) 対応で `--break-system-packages` も必要になり、ホスト環境を汚す。却下。
- **ホスト venv / uv**: rclpy は apt から入るため PYTHONPATH の両立コストが発生する (ADR 0002 で既に却下理由を記載)。却下。
- **既存 `robot` image に Parakeet/NeMo toolkit を相乗り**: 10GB 超のベースが実機側にも要求され、ビルド時間・メモリフットプリントが悪化。他ノードまで巻き添えになる。却下。
- **機能別 profile (`voice_teleop` 等)**: runtime 粒度が揃わない。runtime 命名に統一して機能増加時の拡張性を確保する。却下。
- **NeMo を ONNX / TensorRT 化して軽量化**: 将来の最適化としては有効だが、arm64 + Blackwell 向けのビルドパイプラインが整っていない。第一版では見送り。
- **Isaac ROS repository を ROS 公式 repo の代わりに使う**: 2026-04-19 時点の Isaac ROS docs でも ROS 2 Jazzy 自体は公式 ROS 2 手順で導入する前提であり、Isaac ROS apt repository は pre-built Isaac ROS packages の追加配布元という位置付け。ROS 基盤まで NVIDIA 側に寄せると責務が曖昧になるため却下。

## Consequences

- voice_teleop を動かす標準手順が `docker compose --profile dgx-spark up` に集約される。ホスト実行オプションは廃止。
- dgx-spark image サイズは 10GB を超える見込み。初回 build / pull に時間がかかる。
- モデル初回 DL (数百 MB〜1GB) は `~/.cache/huggingface` にキャッシュされ、2 回目以降は即起動。
- Azure backend を比較用に併用する場合も、Realtime API クライアント依存は `dgx-spark` image に閉じ込める。ホスト側に追加の Python 依存は入れない。
- `dgx-spark` image は ROS 公式 apt source と Isaac ROS apt source の両方を持つため、将来 Isaac ROS パッケージを追加するときに Dockerfile 変更は最小限で済む。
- `dgx-spark` は Jazzy ベースの GPU ノード実行環境であり、`src/ros/unitree_ros2` をそのまま build/run する責務は持たない。robot 近傍の `unitree_ros2` 運用は Humble 側に残し、DGX Spark 側は bridge/zenoh 越し topic を利用する。
- `robot` と DGX Spark runtime は同時起動可能だが、いずれも `network_mode: host` を使うため ROS_DOMAIN_ID / zenoh ポートの衝突に注意する運用ルールは別途必要。
- 将来 DGX Spark 上で別の ML ノードが増えた場合、`Dockerfile.dgx-spark-jazzy` に pip 追加するだけで本 ADR の再評価は不要。依存トポロジが大きく変わる場合のみ新 ADR を起票する。
