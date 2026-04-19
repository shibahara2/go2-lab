# ADR 0002: Python ノードの実行環境管理

- Status: Accepted
- Date: 2026-04-18
- Related: ADR 0001 (voice_teleop)

## Context

ADR 0001 で voice_teleop を ament_python パッケージとして導入した際、Python 依存 (`python3-websockets`) は pip ではなく apt で管理する方針を採った。そのときは `configs/deps/packages.txt` に手で追記していた。今後 `src/ros/` 配下に Python ノードが増える見込みで、以下を決める必要がある。

- 各ノードが使う Python ライブラリをどこに書くか (source of truth)
- workstation ホストと Jetson コンテナで同じ仕組みを使うか
- バージョン固定や lockfile をどう扱うか

前提として、当面追加される Python ノードは ROS 周辺の標準的なライブラリ (apt で入る範囲) で十分と想定する。ML / 新しめの SDK のように apt 版が存在しない / 古すぎる依存は当面使わない。

## Decision

各 ROS パッケージの `package.xml` を Python 依存の単一の source of truth とし、`rosdep install --from-paths src/ros --ignore-src -r -y` で apt に解決させる。workstation / Jetson 双方で `make host-deps-install` を使う。pip / venv / uv は今の段階では導入しない。

1. **source of truth**: `src/ros/<pkg>/package.xml` の `<exec_depend>` に rosdep キー (例: `python3-websockets`, `python3-numpy`, `alsa-utils`) を列挙する。
2. **`configs/deps/packages.txt` の役割縮小**: build tool と ROS ワークスペース全体で共通に要る apt パッケージだけに絞る。ノード固有の Python 依存は書かない。
3. **インストール経路の統一**: `make host-deps-install` は (a) packages.txt の apt install と (b) `rosdep install --from-paths src/ros` の 2 段を持つ。workstation ホストでも Jetson コンテナでも同じコマンドを実行する。
4. **lockfile なし**: rosdistro + apt が返すバージョンに従う。再現性はデモ / 実験用途として十分とみなす。
5. **apt に無い依存が要る場合**: その時点で新 ADR を起票し、venv / uv の導入可否を決める。現状のプロジェクトに先回りで pip を入れない。

## Alternatives considered

- **`configs/deps/packages.txt` に全部書き続ける**: 単一ファイルで一覧性は高いが、ノード追加のたびに別ファイルを触ることになり、パッケージ単位で完結しない。却下。
- **repo 直下に `pyproject.toml` + uv で venv 管理**: lockfile で再現性は取れるが、rclpy が apt 経由で入るため venv の `site-packages` と ROS の PYTHONPATH を両立させる運用コストが出る。apt で足りる現状では過剰。却下 (将来必要になったら再検討)。
- **Dockerfile ビルド時に `rosdep install` する**: ソースがビルド時点で image に入っていない (compose で bind mount) ため、Dockerfile の段階でパッケージごとの依存は確定しない。却下。

## Consequences

- 新しい Python ノードを足すときに触るファイルが `package.xml` に集約される。`configs/deps/packages.txt` は共通項だけに保たれる。
- `python3-rosdep` が `configs/deps/packages.txt` に残ることが前提になる。既に残っている。
- `rosdep init` / `rosdep update` が初回必要。`host-deps-install` が冪等に扱う。
- rosdep キーが存在しないライブラリ (珍しい PyPI 専用パッケージ) が必要になった時点で本 ADR は再検討対象になる。その場合の選択肢は: (a) rosdep の custom rules ファイルを `configs/` 配下に置く、(b) venv / uv を新規導入する、(c) 当該ノードだけコンテナ内で pip install する、のいずれか。新 ADR で決める。
