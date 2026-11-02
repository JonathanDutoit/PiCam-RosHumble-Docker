#!/bin/bash
set -e
source /opt/ros/humble/setup.bash

cd "$ROS_WS"
echo "[entrypoint] Building workspace..."
colcon build --symlink-install

if [ -f "$ROS_WS/install/setup.bash" ]; then
    source "$ROS_WS/install/setup.bash"
else
    echo "[entrypoint] WARNING: /$ROS_WS/install/setup.bash not found, skipping"
fi

exec "$@"
