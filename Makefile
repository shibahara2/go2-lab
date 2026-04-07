DOCKER_COMPOSE = docker compose -f docker/docker-compose.yml --env-file .env
SYNC_CONFIGS = ./scripts/sync_configs.sh
ROS_SRC_PREFIX = src/ros/
ZENOH_BUILD_ROOTS = src/zenoh src/zenoh-plugin-ros2dds

.PHONY: help build up down ps logs shell sync-configs colcon-build zenoh-build zenoh-client target-build host-deps-install livox-sdk-install

help:
	@echo "Usage:"
	@echo "  Default mode: DISTRIBUTED_MODE=0 (workstation host + optional Jetson container)"
	@echo "  make build                            # build Jetson services"
	@echo "  make up                               # run Jetson services in background"
	@echo "  make shell                            # enter Jetson container"
	@echo "  ./scripts/visualization_host_shell.sh # open host shell with auto env/source"
	@echo "  make sync-configs                     # sync tracked configs into src/ and configs/"
	@echo "  make colcon-build                      # build ROS packages under $(ROS_SRC_PREFIX) only"
	@echo "  make target-build                      # build ROS packages; include zenoh only in distributed mode"
	@echo "  make zenoh-build                       # distributed mode only"
	@echo "  make zenoh-client                      # distributed mode only"
	@echo "  make host-deps-install                # install system/ROS packages for host builds"
	@echo "  # ROS packages are built from $(ROS_SRC_PREFIX); Rust zenoh workspaces are optional"

build:
	$(DOCKER_COMPOSE) --profile jetson build jetson

up:
	$(DOCKER_COMPOSE) --profile jetson up -d jetson

down:
	$(DOCKER_COMPOSE) --profile jetson down

ps:
	$(DOCKER_COMPOSE) --profile jetson ps

logs:
	$(DOCKER_COMPOSE) --profile jetson logs -f jetson

shell:
	$(CURDIR)/scripts/docker_shell.sh $(CURDIR)

sync-configs:
	@test -f .env || { echo "Error: .env not found. Run: cp .env.example .env"; exit 1; }
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
	if [ -f .env ]; then . ./.env; fi; \
	if [ "$${DISTRIBUTED_MODE:-0}" != "1" ]; then \
		echo "Error: make zenoh-build is available only when DISTRIBUTED_MODE=1."; \
		echo "Default mode uses workstation host + optional Jetson container."; \
		echo "Set DISTRIBUTED_MODE=1 in .env to enable distributed mode."; \
		exit 1; \
	fi; \
	for p in $(ZENOH_BUILD_ROOTS); do \
		if [ ! -f "$$p/Cargo.toml" ]; then continue; fi; \
		echo "cargo build --release ($$p)"; \
		( cd "$$p" && cargo build --release ); \
	done

zenoh-client:
	@set -e; \
	if [ -f .env ]; then . ./.env; fi; \
	if [ "$${DISTRIBUTED_MODE:-0}" != "1" ]; then \
		echo "Error: make zenoh-client is available only when DISTRIBUTED_MODE=1."; \
		echo "Default mode uses workstation host + optional Jetson container."; \
		echo "Set DISTRIBUTED_MODE=1 in .env to enable distributed mode."; \
		exit 1; \
	fi; \
	./scripts/run_zenoh_client.sh

target-build: colcon-build
	@set -e; \
	if [ -f .env ]; then . ./.env; fi; \
	if [ "$${DISTRIBUTED_MODE:-0}" = "1" ]; then \
		$(MAKE) zenoh-build; \
	else \
		echo "Skipping zenoh-build because DISTRIBUTED_MODE=$${DISTRIBUTED_MODE:-0}."; \
	fi

host-deps-install:
	sudo apt-get update && \
	grep -v '^\s*#' configs/deps/packages.txt | grep -v '^\s*$$' | \
	xargs sudo apt-get install -y

livox-sdk-install:
	cd src/Livox-SDK2 && mkdir -p build && cd build && cmake .. && make -j$$(nproc) && sudo make install
