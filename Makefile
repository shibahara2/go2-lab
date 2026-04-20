BASE_DOCKER_COMPOSE = docker compose -f docker/docker-compose.yml --env-file .env
DGX_SPARK_DOCKER_COMPOSE = docker compose -f docker/docker-compose.yml -f docker/docker-compose.dgx-spark.yml --env-file .env
SYNC_CONFIGS = ./scripts/sync_configs.sh
ROS_SRC_PREFIX = src/ros/
ZENOH_BUILD_ROOTS = src/zenoh src/zenoh-plugin-ros2dds

.PHONY: help build up down ps logs shell \
	robot-build robot-up robot-down robot-ps robot-logs robot-shell \
	workstation-build workstation-up workstation-down workstation-ps workstation-logs workstation-shell \
	sync-configs colcon-build zenoh-build zenoh-client target-build host-deps-install livox-sdk-install \
	dgx-spark-build dgx-spark-up dgx-spark-down \
	dgx-spark-humble-build dgx-spark-humble-up dgx-spark-humble-down dgx-spark-humble-shell \
	dgx-spark-jazzy-build dgx-spark-jazzy-up dgx-spark-jazzy-down dgx-spark-jazzy-shell dgx-spark-shell

help:
	@echo "Usage:"
	@echo "  Default mode: DISTRIBUTED_MODE=0 (workstation host GUI + workstation container)"
	@echo "  make robot-build                       # build robot runtime"
	@echo "  make robot-up                          # run robot runtime in background"
	@echo "  make robot-shell                       # enter robot container"
	@echo "  make workstation-build                 # build workstation runtime"
	@echo "  make workstation-up                    # run workstation runtime in background"
	@echo "  make workstation-shell                 # enter workstation container"
	@echo "  ./scripts/visualization_host_shell.sh  # open host GUI shell with auto env/source"
	@echo "  make dgx-spark-build                   # build both DGX Spark runtimes"
	@echo "  make dgx-spark-up                      # run DGX Spark Humble + Jazzy runtimes"
	@echo "  make dgx-spark-humble-shell            # enter DGX Spark Humble container"
	@echo "  make dgx-spark-jazzy-shell             # enter DGX Spark Jazzy container"
	@echo "  make sync-configs                      # sync tracked configs into src/ and configs/"
	@echo "  make target-build                      # build ROS packages; include zenoh only in distributed mode"

build: robot-build
up: robot-up
down: robot-down
ps: robot-ps
logs: robot-logs
shell: robot-shell

robot-build:
	$(BASE_DOCKER_COMPOSE) --profile robot build robot

robot-up:
	$(BASE_DOCKER_COMPOSE) --profile robot up -d robot

robot-down:
	-$(BASE_DOCKER_COMPOSE) stop robot
	-$(BASE_DOCKER_COMPOSE) rm -f robot

robot-ps:
	$(BASE_DOCKER_COMPOSE) ps robot

robot-logs:
	$(BASE_DOCKER_COMPOSE) logs -f robot

robot-shell:
	$(CURDIR)/scripts/robot_shell.sh

workstation-build:
	$(BASE_DOCKER_COMPOSE) --profile workstation build workstation

workstation-up:
	$(BASE_DOCKER_COMPOSE) --profile workstation up -d workstation

workstation-down:
	-$(BASE_DOCKER_COMPOSE) stop workstation
	-$(BASE_DOCKER_COMPOSE) rm -f workstation

workstation-ps:
	$(BASE_DOCKER_COMPOSE) ps workstation

workstation-logs:
	$(BASE_DOCKER_COMPOSE) logs -f workstation

workstation-shell:
	$(CURDIR)/scripts/workstation_shell.sh

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
		echo "Default mode uses workstation host GUI + workstation container."; \
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
		echo "Default mode uses workstation host GUI + workstation container."; \
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
	grep -hv '^[[:space:]]*#' configs/deps/packages.txt configs/deps/workstation-packages.txt | grep -hv '^[[:space:]]*$$' | \
	xargs sudo apt-get install -y
	@if [ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]; then \
		sudo rosdep init; \
	fi
	rosdep update
	rosdep install --from-paths src/ros --ignore-src -r -y

livox-sdk-install:
	cd src/Livox-SDK2 && mkdir -p build && cd build && cmake .. && make -j$$(nproc) && sudo make install

dgx-spark-build: dgx-spark-humble-build dgx-spark-jazzy-build

dgx-spark-up: dgx-spark-humble-up dgx-spark-jazzy-up

dgx-spark-down: dgx-spark-humble-down dgx-spark-jazzy-down

dgx-spark-humble-build:
	$(DGX_SPARK_DOCKER_COMPOSE) --profile dgx-spark-humble build dgx-spark-humble

dgx-spark-humble-up:
	$(DGX_SPARK_DOCKER_COMPOSE) --profile dgx-spark-humble up -d dgx-spark-humble

dgx-spark-humble-down:
	-$(DGX_SPARK_DOCKER_COMPOSE) stop dgx-spark-humble
	-$(DGX_SPARK_DOCKER_COMPOSE) rm -f dgx-spark-humble

dgx-spark-humble-shell:
	$(CURDIR)/scripts/dgx_spark_humble_shell.sh

dgx-spark-jazzy-build:
	$(DGX_SPARK_DOCKER_COMPOSE) --profile dgx-spark-jazzy build dgx-spark-jazzy

dgx-spark-jazzy-up:
	$(DGX_SPARK_DOCKER_COMPOSE) --profile dgx-spark-jazzy up -d dgx-spark-jazzy

dgx-spark-jazzy-down:
	-$(DGX_SPARK_DOCKER_COMPOSE) stop dgx-spark-jazzy
	-$(DGX_SPARK_DOCKER_COMPOSE) rm -f dgx-spark-jazzy

dgx-spark-jazzy-shell:
	$(CURDIR)/scripts/dgx_spark_jazzy_shell.sh

dgx-spark-shell: dgx-spark-jazzy-shell
