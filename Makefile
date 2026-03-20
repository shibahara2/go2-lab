TARGET ?= jetson
DOCKER_COMPOSE = docker compose -f $(CURDIR)/docker/docker-compose.yml
SYNC_CONFIGS = ./scripts/sync_configs.sh
VISUALIZATION_HOST_SHELL = ./scripts/visualization_host_shell.sh
ROS_SRC_PREFIX = src/ros/
ZENOH_BUILD_ROOTS = src/zenoh src/zenoh-plugin-ros2dds
ALL_TARGETS = jetson bridge visualization-host
DOCKER_TARGETS = jetson bridge

.PHONY: help build up down ps logs shell sync-configs colcon-build zenoh-build target-build require-docker-target host-deps-install livox-sdk-install docker-env

help:
	@echo "Usage:"
	@echo "  TARGET values: $(ALL_TARGETS)"
	@echo "  Docker-capable TARGET values: $(DOCKER_TARGETS)"
	@echo "  make build TARGET=jetson              # build Jetson services"
	@echo "  make build TARGET=bridge              # build bridge services"
	@echo "  make up TARGET=jetson                 # run services in background"
	@echo "  make shell TARGET=jetson              # enter primary container"
	@echo "  make shell TARGET=visualization-host  # open host shell with auto env/source"
	@echo "  make sync-configs          # copy tracked config templates into src/"
	@echo "  make colcon-build                      # build ROS packages under $(ROS_SRC_PREFIX) only"
	@echo "  make zenoh-build                       # build $(ZENOH_BUILD_ROOTS)"
	@echo "  make target-build                      # build ROS + Rust with one command"
	@echo "  make host-deps-install                # install system/ROS packages for host builds"
	@echo "  # ROS packages are built from $(ROS_SRC_PREFIX), Rust from $(ZENOH_BUILD_ROOTS)"

require-docker-target:
	@echo "$(DOCKER_TARGETS)" | grep -qw "$(TARGET)" || { \
		echo "Unsupported docker TARGET='$(TARGET)'."; \
		echo "Docker commands are available only for: $(DOCKER_TARGETS)"; \
		echo "Use colcon-build/zenoh-build/target-build for non-Docker targets."; \
		exit 1; \
	}

docker-env:
	@echo "USER=$(shell whoami)" > docker/.env
	@echo "UID=$(shell id -u)" >> docker/.env
	@echo "GID=$(shell id -g)" >> docker/.env

build: require-docker-target docker-env
	$(DOCKER_COMPOSE) --profile $(TARGET) build $(TARGET)

up: require-docker-target
	$(DOCKER_COMPOSE) --profile $(TARGET) up -d $(TARGET)

down: require-docker-target
	$(DOCKER_COMPOSE) --profile $(TARGET) down

ps: require-docker-target
	$(DOCKER_COMPOSE) --profile $(TARGET) ps

logs: require-docker-target
	$(DOCKER_COMPOSE) --profile $(TARGET) logs -f $(TARGET)

shell:
	@if [ "$(TARGET)" = "visualization-host" ]; then \
		bash $(VISUALIZATION_HOST_SHELL); \
	elif echo "$(DOCKER_TARGETS)" | grep -qw "$(TARGET)"; then \
		cd / && $(DOCKER_COMPOSE) exec -w /workspace $(TARGET) bash -lc 'cd /workspace; \
			if [ -f /workspace/src/ros/unitree_ros2/setup.sh ]; then \
				source /workspace/src/ros/unitree_ros2/setup.sh; \
				echo "[auto-source] sourced: /workspace/src/ros/unitree_ros2/setup.sh"; \
			else \
				echo "[auto-source] missing: /workspace/src/ros/unitree_ros2/setup.sh"; \
			fi; \
			if [ -f /workspace/install/setup.bash ]; then \
				source /workspace/install/setup.bash; \
				echo "[auto-source] sourced: /workspace/install/setup.bash"; \
			else \
				echo "[auto-source] missing: /workspace/install/setup.bash"; \
			fi; \
			exec bash -i'; \
	else \
		echo "Unsupported shell TARGET='"'"'$(TARGET)'"'"'."; \
		echo "Shell is available for: $(ALL_TARGETS)"; \
		exit 1; \
	fi

sync-configs:
	$(SYNC_CONFIGS)

colcon-build:
	@set -e; \
	find src/ros -name "package_ROS2.xml" | while IFS= read -r f; do \
		dir=$$(dirname "$$f"); \
		if [ ! -f "$$dir/package.xml" ]; then \
			echo "Copying $$f -> $$dir/package.xml"; \
			cp "$$f" "$$dir/package.xml"; \
		fi; \
	done; \
	find src/ros -name "launch_ROS2" -type d | while IFS= read -r d; do \
		target_dir="$$(dirname "$$d")/launch"; \
		if [ ! -d "$$target_dir" ]; then \
			echo "Copying $$d -> $$target_dir"; \
			cp -rf "$$d" "$$target_dir"; \
		fi; \
	done; \
	colcon build --base-paths src/ros --symlink-install \
		--cmake-args -DROS_EDITION=ROS2 -DHUMBLE_ROS=humble

zenoh-build:
	@set -e; \
	for p in $(ZENOH_BUILD_ROOTS); do \
		if [ ! -f "$$p/Cargo.toml" ]; then continue; fi; \
		echo "cargo build --release ($$p)"; \
		( cd "$$p" && cargo build --release ); \
	done

target-build: colcon-build zenoh-build

host-deps-install:
	sudo apt-get update && \
	grep -v '^\s*#' configs/deps/packages.txt | grep -v '^\s*$$' | \
	xargs sudo apt-get install -y

livox-sdk-install:
	cd src/Livox-SDK2 && mkdir -p build && cd build && cmake .. && make -j$$(nproc) && sudo make install
