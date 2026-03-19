TARGET ?= jetson
DOCKER_COMPOSE = docker compose -f docker/docker-compose.yml
SYNC_CONFIGS = ./scripts/sync_configs.sh
VISUALIZATION_HOST_SHELL = ./scripts/visualization_host_shell.sh
STAGE_DIR ?= .staging/$(TARGET)
ROS_SRC_PREFIX = src/ros/
ZENOH_BUILD_ROOTS = src/zenoh src/zenoh-plugin-ros2dds
ALL_TARGETS = jetson bridge visualization-host
DOCKER_TARGETS = jetson bridge

ifeq ($(TARGET),jetson)
PROFILE = jetson
SERVICES = jetson
PRIMARY_SERVICE = jetson
else ifeq ($(TARGET),bridge)
PROFILE = bridge
SERVICES = bridge
PRIMARY_SERVICE = bridge
else
PROFILE =
SERVICES =
PRIMARY_SERVICE =
endif

.PHONY: help build up down ps logs shell sync-configs colcon-build zenoh-build target-build require-docker-target host-deps-install livox-sdk-install

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
	@echo "  make colcon-build TARGET=jetson        # build ROS packages under $(ROS_SRC_PREFIX) only"
	@echo "  make zenoh-build TARGET=visualization-host # build $(ZENOH_BUILD_ROOTS)"
	@echo "  make target-build TARGET=visualization-host # build ROS + Rust with one command"
	@echo "  make host-deps-install                # install system/ROS packages for host builds"
	@echo "  # ROS packages are built from $(ROS_SRC_PREFIX), Rust from $(ZENOH_BUILD_ROOTS)"

require-docker-target:
	@if [ -z "$(SERVICES)" ]; then \
		echo "Unsupported docker TARGET='$(TARGET)'."; \
		echo "Docker commands are available only for: $(DOCKER_TARGETS)"; \
		echo "Use colcon-build/zenoh-build/target-build for non-Docker targets."; \
		exit 1; \
	fi

build: require-docker-target
	$(DOCKER_COMPOSE) --profile $(PROFILE) build $(SERVICES)

up: require-docker-target
	$(DOCKER_COMPOSE) --profile $(PROFILE) up -d $(SERVICES)

down: require-docker-target
	$(DOCKER_COMPOSE) --profile $(PROFILE) down

ps: require-docker-target
	$(DOCKER_COMPOSE) --profile $(PROFILE) ps

logs: require-docker-target
	$(DOCKER_COMPOSE) --profile $(PROFILE) logs -f $(SERVICES)

shell:
	@if [ "$(TARGET)" = "visualization-host" ]; then \
		bash $(VISUALIZATION_HOST_SHELL); \
	elif [ -n "$(SERVICES)" ]; then \
		$(DOCKER_COMPOSE) exec $(PRIMARY_SERVICE) bash -lc 'cd /workspace; \
			if [ "$(TARGET)" = "jetson" ]; then \
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
			fi; \
			exec bash -i'; \
	else \
		echo "Unsupported shell TARGET='$(TARGET)'."; \
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
ifeq ($(TARGET),visualization-host)
	cd src/Livox-SDK2 && mkdir -p build && cd build && cmake .. && make -j$$(nproc) && sudo make install
else ifeq ($(TARGET),jetson)
	$(DOCKER_COMPOSE) --profile jetson exec jetson bash -lc \
		'cd /workspace/src/Livox-SDK2 && mkdir -p build && cd build && cmake .. && make -j$$(nproc) && make install'
else
	@echo "livox-sdk-install supports TARGET=jetson or TARGET=visualization-host"; exit 1
endif
