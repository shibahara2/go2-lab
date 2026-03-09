TARGET ?= jetson
DOCKER_COMPOSE = docker compose -f docker/docker-compose.yml
LIST_TARGET_SRC = ./scripts/list_target_src.sh
STAGE_DIR ?= .staging/$(TARGET)

ifeq ($(TARGET),jetson)
PROFILE = jetson
SERVICES = fast-lio-ros2
PRIMARY_SERVICE = fast-lio-ros2
else ifeq ($(TARGET),desktop)
PROFILE = desktop
SERVICES = unitree_ros2-azure
PRIMARY_SERVICE = unitree_ros2-azure
else
PROFILE =
SERVICES =
PRIMARY_SERVICE =
endif

.PHONY: help build up down ps logs shell src-list src-stage colcon-build zenoh-build target-build require-docker-target

help:
	@echo "Usage:"
	@echo "  make build TARGET=jetson   # build Jetson services"
	@echo "  make build TARGET=desktop  # build desktop services"
	@echo "  make up TARGET=jetson      # run services in background"
	@echo "  make shell TARGET=jetson   # enter primary container"
	@echo "  make src-list TARGET=jetson # list src paths for target"
	@echo "  make src-stage TARGET=jetson STAGE_DIR=.staging/jetson"
	@echo "  make colcon-build TARGET=desktop # build only target-classified ROS paths"
	@echo "  make zenoh-build TARGET=desktop  # build target-classified Rust workspaces"
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
	$(DOCKER_COMPOSE) exec $(PRIMARY_SERVICE) bash

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

colcon-build:
	@set -e; \
	paths="$$( $(LIST_TARGET_SRC) $(TARGET) | while IFS= read -r p; do \
		if [ -f "$$p/package.xml" ] || [ -f "$$p/package_ROS2.xml" ]; then \
			printf '%s ' "$$p"; \
		fi; \
	done )"; \
	if [ -z "$$paths" ]; then \
		echo "No ROS package paths found for TARGET=$(TARGET); skipping colcon build."; \
		exit 0; \
	fi; \
	echo "colcon base paths:$$paths"; \
	colcon build --base-paths $$paths --symlink-install --packages-skip turtlesim

zenoh-build:
	@set -e; \
	paths="$$( $(LIST_TARGET_SRC) $(TARGET) | while IFS= read -r p; do \
		if [ -f "$$p/Cargo.toml" ]; then \
			printf '%s\n' "$$p"; \
		fi; \
	done )"; \
	if [ -z "$$paths" ]; then \
		echo "No Rust workspace paths found for TARGET=$(TARGET); skipping cargo build."; \
		exit 0; \
	fi; \
	echo "$$paths" | while IFS= read -r p; do \
		[ -z "$$p" ] && continue; \
		echo "cargo build --release ($$p)"; \
		( cd "$$p" && cargo build --release ); \
	done

target-build: colcon-build zenoh-build
