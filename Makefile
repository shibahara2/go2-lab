TARGET ?= jetson
DOCKER_COMPOSE = docker compose -f docker/docker-compose.yml
LIST_TARGET_SRC = ./scripts/list_target_src.sh
SYNC_CONFIGS = ./scripts/sync_configs.sh
STAGE_DIR ?= .staging/$(TARGET)
ROS_SRC_PREFIX = src/ros/
ZENOH_BUILD_ROOTS = src/zenoh src/zenoh-plugin-ros2dds

ifeq ($(TARGET),jetson)
PROFILE = jetson
SERVICES = jetson
PRIMARY_SERVICE = jetson
else ifeq ($(TARGET),desktop)
PROFILE = desktop
SERVICES = desktop
PRIMARY_SERVICE = desktop
else
PROFILE =
SERVICES =
PRIMARY_SERVICE =
endif

.PHONY: help build up down ps logs shell src-list src-stage sync-configs colcon-build zenoh-build target-build require-docker-target

help:
	@echo "Usage:"
	@echo "  make build TARGET=jetson   # build Jetson services"
	@echo "  make build TARGET=desktop  # build desktop services"
	@echo "  make up TARGET=jetson      # run services in background"
	@echo "  make shell TARGET=jetson   # enter primary container"
	@echo "  make src-list TARGET=jetson # list src paths for target"
	@echo "  make src-stage TARGET=jetson STAGE_DIR=.staging/jetson"
	@echo "  make sync-configs          # copy tracked config templates into src/"
	@echo "  make colcon-build TARGET=desktop # build ROS packages under $(ROS_SRC_PREFIX) only"
	@echo "  make zenoh-build TARGET=desktop  # build $(ZENOH_BUILD_ROOTS)"
	@echo "  make target-build TARGET=desktop # build ROS + Rust with one command"
	@echo "  # add future targets via configs/deploy/src-<target>.txt"

require-docker-target:
	@if [ -z "$(SERVICES)" ]; then \
		echo "Unsupported docker TARGET='$(TARGET)'."; \
		echo "Add mapping in Makefile (PROFILE/SERVICES/PRIMARY_SERVICE)."; \
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

shell: require-docker-target
	$(DOCKER_COMPOSE) exec $(PRIMARY_SERVICE) bash -lc 'cd /workspace; \
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
		exec bash -i'

src-list:
	$(LIST_TARGET_SRC) $(TARGET)

src-stage:
	rm -rf $(STAGE_DIR)
	mkdir -p $(STAGE_DIR)
	@set -e; \
	for p in $$($(LIST_TARGET_SRC) $(TARGET)); do \
		if [ ! -e "$$p" ]; then \
			echo "Skip missing path: $$p"; \
			continue; \
		fi; \
		mkdir -p "$(STAGE_DIR)/$$(dirname "$$p")"; \
		rsync -a --exclude '.git' "$$p/" "$(STAGE_DIR)/$$p/"; \
	done
	@echo "Staged source set for $(TARGET): $(STAGE_DIR)"

sync-configs:
	$(SYNC_CONFIGS)

colcon-build:
	@set -e; \
	paths="$$( $(LIST_TARGET_SRC) $(TARGET) | while IFS= read -r p; do \
		case "$$p" in $(ROS_SRC_PREFIX)*) ;; *) continue ;; esac; \
		printf '%s ' "$$p"; \
	done )"; \
	if [ -z "$$paths" ]; then \
		echo "No $(ROS_SRC_PREFIX) search roots found for TARGET=$(TARGET); skipping colcon build."; \
		exit 0; \
	fi; \
	echo "colcon base paths ($(ROS_SRC_PREFIX) only):$$paths"; \
	colcon build --base-paths $$paths --symlink-install --packages-skip turtlesim

zenoh-build:
	@set -e; \
	paths="$$( $(LIST_TARGET_SRC) $(TARGET) | while IFS= read -r p; do \
		for root in $(ZENOH_BUILD_ROOTS); do \
			if [ "$$p" = "$$root" ] && [ -f "$$p/Cargo.toml" ]; then \
				printf '%s\n' "$$p"; \
				break; \
			fi; \
		done; \
	done )"; \
	if [ -z "$$paths" ]; then \
		echo "No zenoh Rust workspace paths ($(ZENOH_BUILD_ROOTS)) found for TARGET=$(TARGET); skipping cargo build."; \
		exit 0; \
	fi; \
	echo "$$paths" | while IFS= read -r p; do \
		[ -z "$$p" ] && continue; \
		echo "cargo build --release ($$p)"; \
		( cd "$$p" && cargo build --release ); \
	done

target-build: colcon-build zenoh-build
