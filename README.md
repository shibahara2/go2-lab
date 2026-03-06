# SLAM
[Unitree Go2 Mid360でSLAMを実行する](https://techshare.co.jp/faq/unitree/mid360_slam_fast-lio.html)
- [x] macでimageをビルドできるか確認
- [x] macでコンテナ動作はできなかった: NVIDIA GPUがないから
- [ ] このリポジトリに入れる
- [ ] Jetsonでimageビルド、コンテナ実行できるか確認

# MEMO
- livox_ros_driver2をビルドしたい。build.shを使うと他のrosパッケージまで巻き込まれる。colcon buildにするとcmakeに適切な引数が渡らずエラーになる。

## External Repos (vcstool)

`FAST_LIO` / `livox_ros_driver2` など外部リポジトリは `go2.repos` で取得可能。

mac での `vcstool` セットアップ（uv）:

```bash
cd /Users/shibahara/Sandbox/go2-lab
uv init -p 3.12 .
uv tool install --with 'setuptools<81' vcstool
```

`uv` でインストールした場合の実行例:

```bash
cd /Users/shibahara/Sandbox/go2-lab
uvx vcs import --force < go2.repos
uvx vcs pull $(uvx vcs list < go2.repos)
```

Jetson/Ubuntu での `vcstool` セットアップ:

```bash
# 1) vcstool を入れる
sudo apt-get update
sudo apt-get install -y python3-vcstool

# 2) このリポジトリのルートで実行
cd /home/unitree/go2-lab
vcs import --force < go2.repos
```

更新:

```bash
cd /home/unitree/go2-lab
vcs pull $(vcs list < go2.repos)
```

注:
- このリポジトリは submodule を使わず、外部依存は `go2.repos` + `vcstool` で管理する。
- `src/ros/livox_ros_driver2/config/MID360_config.json` は `configs/livox/MID360_config.json` を正として管理する。

MID360 設定の反映:

```bash
cd /home/unitree/go2-lab
cp configs/livox/MID360_config.json src/ros/livox_ros_driver2/config/MID360_config.json
```

## fast-lio-ros2 (docker compose)

`fast-lio-ros2` コンテナでホストと同じ構成 (`/workspace/src/ros/...`) を使ってビルドする手順:

```bash
cd docker
docker compose build fast-lio-ros2
docker compose up -d fast-lio-ros2
docker compose exec fast-lio-ros2 bash
```

コンテナ内で実行:

```bash
# FAST_LIO の依存 (ikd-Tree) が無い場合のみ取得
if [ ! -f /workspace/src/ros/FAST_LIO/include/ikd-Tree/ikd_Tree.cpp ]; then
  rm -rf /workspace/src/ros/FAST_LIO/include/ikd-Tree
  git clone https://github.com/hku-mars/ikd-Tree.git /workspace/src/ros/FAST_LIO/include/ikd-Tree
fi

source /opt/ros/humble/setup.bash
cd /workspace
colcon build --base-paths src/ros --symlink-install \
  --packages-skip turtlesim
source install/setup.bash
```

起動例:

```bash
ros2 launch livox_ros_driver2 msg_MID360_launch.py
ros2 launch fast_lio mapping_mid360.launch.py
```
