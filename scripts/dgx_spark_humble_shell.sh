#!/usr/bin/env zsh
set -euo pipefail

"$(cd "$(dirname "$0")" && pwd)/service_shell.sh" dgx-spark-humble /opt/ros/humble/setup.zsh yes
