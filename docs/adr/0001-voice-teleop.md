# ADR 0001: 音声による Go2 teleop の構成

- Status: Accepted
- Date: 2026-04-18
- Related: Issue #6

## Context

Issue #6 で、Azure OpenAI Realtime API を用いて音声発話から Go2 を動かすサンプルコードが提示された。このサンプルは以下の特徴を持つ。

- `ros2 topic pub --once` を subprocess で呼び出して `/turtle1/cmd_vel` を publish する
- 環境変数 `AZURE_OPENAI_API_KEY` と固定の WebSocket エンドポイントを使う
- 前進 / 左 / 右 / 停止 の 4 コマンドに対応する

本リポジトリ (`go2-lab`) は分散モード (`DISTRIBUTED_MODE=1`) で workstation + external zenoh router + robot の三者構成を持ち、`src/ros/cmd_vel_control` が `/cmd_vel` (geometry_msgs/Twist) を `/api/sport/request` (unitree_api/Request) に変換して Go2 本体に届ける既存経路がある。サンプルをそのまま持ち込むと以下の不一致がある。

- トピックが `/turtle1/cmd_vel` で Go2 経路と噛み合わない
- subprocess 起動は 100ms 単位のレイテンシと失敗時のゾンビ化が避けられない
- ROS ノードとして扱えないため colcon ビルド・launch・他ノードとの依存管理に載らない

workstation から発話で Go2 を動かすエンドツーエンドの経路を、既存の分散モード経路を再利用する形で整える必要がある。

## Decision

1. **パッケージ配置**: `src/ros/voice_teleop/` に ament_python パッケージを新設する。colcon ビルド対象に入り、`ros2 run voice_teleop voice_teleop` で起動できるようにする。
2. **publish 経路**: 自前で `/api/sport/request` を組まず、既存の `cmd_vel_control` に任せるため `/cmd_vel` (geometry_msgs/Twist) を直接 publish する。robot 側に新規コードは追加しない。
3. **publisher 実装**: `rclpy.Node` を継承し `/cmd_vel` publisher を 1 本持続保持する。subprocess 起動は廃止する。
4. **音声入出力**: サンプル同様 `arecord` / `aplay` を subprocess で扱う。双方向音声のためのライブラリは新規追加しない (`alsa-utils` のみ)。
5. **Azure Realtime 接続**: Python の `websockets` ライブラリを使用する。本リポジトリでは Python 依存を pip ではなく apt (`configs/deps/packages.txt`) で管理する方針のため、`python3-websockets` を追加する。apt 版 (Ubuntu 22.04/24.04 で v10/v11) に合わせ `websockets.connect()` には `extra_headers=` を渡す (v13 で追加された `additional_headers` は使わない)。`AZURE_OPENAI_API_KEY` は起動環境変数から読む。
6. **コマンド範囲 (v1)**: 前進 / 後退 / 左旋回 / 右旋回 / 停止 の 5 コマンド。速度はノード内定数。発話ごとの cooldown をサンプル同様に持つ。
7. **設定の持ち方**: `AZURE_OPENAI_API_KEY`, `AZURE_OPENAI_ENDPOINT`, `VOICE_CAPTURE_DEV` を `.env` に追加する。`.env` は git 管理外 (`.env.example` のみ追跡) で、`scripts/sync_configs.sh` が `set -a; source .env` で export するため ROS ノードの環境変数として到達する。
8. **sport_mode の管理**: sport_mode のロック解除や姿勢遷移は voice_teleop の責務外とする。運用者が別手順で行う。

## Alternatives considered

- **standalone `scripts/voice_teleop.py`**: colcon ビルド不要で最速だが、他の ROS ノード (cmd_vel_control, imu_publisher) と起動・依存管理の粒度が揃わない。却下。
- **workstation で `/api/sport/request` を直接 publish**: `cmd_vel_control` を経由しないため robot 側の起動が 1 つ減るが、`unitree_api` の Python バインディングが無く、JSON ペイロードと API ID を自前で組む必要があり保守コストが高い。却下。
- **音声認識を Azure 以外 (Whisper ローカル等)** に抽象化: v1 の範囲を広げすぎる。将来の follow-up とする。
- **連続速度制御 (transcript からの速度推定)**: 発話単位で cooldown を挟む方が誤動作時の安全停止が単純になる。v1 では離散コマンドに限定。

## Consequences

- workstation 側に `python3-websockets` と `alsa-utils` が必要になる。どちらも `configs/deps/packages.txt` に追加し、既存の `make host-deps-install` / Docker ビルドで取り込まれる。pip は使わない。
- 発話 → Go2 動作までの経路に zenoh router が介在するため、router ダウン時は publish が届かず robot は停止しない可能性がある。運用上は停止発話に頼らず物理停止手段 (コントローラ) を併用する。
- Azure 側のトランスクリプト遅延 (数百 ms) が制御レイテンシに乗る。即応性が必要な用途には不向きだが、デモ・実験用途では許容する。
- 将来 voice_teleop を低レベル API (`/api/sport/request` 直叩きや Nav2 ゴール送信) に拡張する場合、本 ADR を更新するか別 ADR を追加する。

## Addendum

- 2026-04-19: ASR バックエンドを Azure Realtime からローカル NeMo ASR (ReazonSpeech) に変更。`dgx-spark` profile の専用コンテナ内で実行する。詳細は ADR 0003。
- 2026-04-19: 比較実験のため、`voice_teleop` は `VOICE_ASR_BACKEND` でローカル Parakeet と Azure Speech Service を切り替え可能にした。VAD と `/cmd_vel` publish 経路は共通化し、backend ごとの差分は transcript と計測ログに限定する。
- 2026-04-20: Azure backend を Azure OpenAI Realtime API に戻した。`parakeet` は既存のローカル energy VAD を維持し、`azure` はローカル VAD を通さず Realtime API の `server_vad` と input audio transcription を使う。コマンド判定と `/cmd_vel` publish は共通のままとする。
- 2026-04-20: Azure backend は transcript をローカル判定せず、Realtime API の STT -> LLM -> function calling を正本にする。利用可能 tool は `step_forward` と `stop_robot` とし、assistant reply は短い日本語をテキスト+音声で返す。
