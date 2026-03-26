TARGET ?=
DOCKER_COMPOSE = docker compose -f docker/docker-compose.yml --env-file .env
SYNC_CONFIGS = ./scripts/sync_configs.sh
VISUALIZATION_HOST_SHELL = ./scripts/visualization_host_shell.sh
ROS_SRC_PREFIX = src/ros/
ZENOH_BUILD_ROOTS = src/zenoh src/zenoh-plugin-ros2dds
ALL_TARGETS = jetson bridge visualization-host
DOCKER_TARGETS = jetson bridge

.PHONY: help build up down ps logs shell sync-configs apply-patches record-patches colcon-build zenoh-build zenoh-client target-build require-target require-docker-target host-deps-install livox-sdk-install

help:
	@echo "Usage:"
	@echo "  TARGET values: $(ALL_TARGETS)"
	@echo "  Docker-capable TARGET values: $(DOCKER_TARGETS)"
	@echo "  make build TARGET=jetson              # build Jetson services"
	@echo "  make build TARGET=bridge              # build bridge services"
	@echo "  make up TARGET=jetson                 # run services in background"
	@echo "  make shell TARGET=jetson              # enter primary container"
	@echo "  make shell TARGET=visualization-host  # open host shell with auto env/source"
	@echo "  make sync-configs TARGET=jetson      # sync tracked configs into src/ and configs/"
	@echo "  make apply-patches                    # apply go2-lab-managed patches to external repos"
	@echo "  make record-patches                   # record local external-repo diffs into go2-lab patches/"
	@echo "  make colcon-build                      # build ROS packages under $(ROS_SRC_PREFIX) only"
	@echo "  make zenoh-build                       # build $(ZENOH_BUILD_ROOTS)"
	@echo "  make zenoh-client                      # run zenoh client with optional ZENOH_CONFIG_OVERRIDE"
	@echo "  make target-build                      # build ROS + Rust with one command"
	@echo "  make host-deps-install                # install system/ROS packages for host builds"
	@echo "  # ROS packages are built from $(ROS_SRC_PREFIX), Rust from $(ZENOH_BUILD_ROOTS)"

require-target:
	@[ -n "$(TARGET)" ] || { \
		echo "Error: TARGET is required."; \
		echo "Usage: make <target> TARGET=<value>"; \
		echo "Available TARGET values: $(ALL_TARGETS)"; \
		exit 1; \
	}

require-docker-target: require-target
	@echo "$(DOCKER_TARGETS)" | grep -qw "$(TARGET)" || { \
		echo "Unsupported docker TARGET='$(TARGET)'."; \
		echo "Docker commands are available only for: $(DOCKER_TARGETS)"; \
		echo "Use colcon-build/zenoh-build/target-build for non-Docker targets."; \
		exit 1; \
	}

build: require-docker-target
	$(DOCKER_COMPOSE) --profile $(TARGET) build $(TARGET)

up: require-docker-target
	$(DOCKER_COMPOSE) --profile $(TARGET) up -d $(TARGET)

down: require-docker-target
	$(DOCKER_COMPOSE) --profile $(TARGET) down

ps: require-docker-target
	$(DOCKER_COMPOSE) --profile $(TARGET) ps

logs: require-docker-target
	$(DOCKER_COMPOSE) --profile $(TARGET) logs -f $(TARGET)

shell: require-target
	@if [ "$(TARGET)" = "visualization-host" ]; then \
		zsh $(VISUALIZATION_HOST_SHELL); \
	elif echo "$(DOCKER_TARGETS)" | grep -qw "$(TARGET)"; then \
		$(CURDIR)/scripts/docker_shell.sh $(CURDIR) $(TARGET); \
	else \
		echo "Unsupported shell TARGET='$(TARGET)'."; \
		echo "Shell is available for: $(ALL_TARGETS)"; \
		exit 1; \
	fi

sync-configs: require-target
	@test -f .env || { echo "Error: .env not found. Run: cp .env.example .env"; exit 1; }
	$(SYNC_CONFIGS) $(TARGET)

apply-patches:
	./scripts/apply_patches.sh

record-patches:
	./scripts/record_patches.sh

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

zenoh-client:
	./scripts/run_zenoh_client.sh

target-build: colcon-build zenoh-build

host-deps-install:
	sudo apt-get update && \
	grep -v '^\s*#' configs/deps/packages.txt | grep -v '^\s*$$' | \
	xargs sudo apt-get install -y

livox-sdk-install:
	cd src/Livox-SDK2 && mkdir -p build && cd build && cmake .. && make -j$$(nproc) && sudo make install
