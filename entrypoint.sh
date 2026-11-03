#!/bin/bash
set -e

source /opt/ros/humble/setup.bash

: "${ROS_WS:=/app/ros2_ws}"
cd "$ROS_WS"

if [ -d "$ROS_WS/src" ]; then
  echo "[entrypoint] Building workspace..."
  colcon build --symlink-install
  if [ -f "$ROS_WS/install/setup.bash" ]; then
    source "$ROS_WS/install/setup.bash"
  fi
else
  echo "[entrypoint] No src/ in $ROS_WS, skipping colcon build"
fi

exec "$@"