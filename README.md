# zenoh-plugin-ros2dds
## clone
```jsx
git clone git@github.com:shibahara2/go2-lab.git
cd go2-lab
git submodule update --init --recursive
```

## コンテナに入る
```jsx
cd docker
docker compose up unitree_ros2-<azure or jetson> -d
docker exec -it unitree_ros2-<azure or jetson> zsh
```

## install rust
```jsx
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source /root/.cargo/env
rustup update
```

## build zenoh
```jsx
cd src/zenoh
cargo build --release
```

## build zenoh-plugin-ros2dds
```jsx
cd src/zenoh-plugin-ros2dds
cargo build --release
```

## build unitree_ros2
```jsx
cd src/unitree_ros2
colcon build
```

## run zenohd
- azure
    ```jsx
    src/zenoh/target/release/zenohd -c zenoh-config-azure.json
      ```

- jetson
    ```jsx
    src/zenoh/target/release/zenohd -c zenoh-config-jetson.json
    ```
