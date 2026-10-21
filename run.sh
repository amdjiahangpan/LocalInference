#!/usr/bin/env bash
# Copyright (C) 2026 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-License-Identifier: MIT
#
# Start the image built by build.sh as a standalone JupyterLab, without
# JupyterHub. The image's default CMD runs jupyterhub.singleuser, which exits
# unless a Hub spawned it, so this replaces it: source ROS and the RAI overlay
# (what start-local-inference.sh does), then serve JupyterLab directly.
#
# Once `docker logs -f auplc-li` shows "Jupyter Server ... is running at", open:
#   http://localhost:8888/lab?token=auplc            on the test machine
#   http://<test-machine-ip>:8888/lab?token=auplc    from another machine
# (defaults shown; substitute PORT/TOKEN if overridden)
#
# Re-running this script replaces the existing container.

set -euo pipefail

IMAGE="${IMAGE:-ghcr.io/amdresearch/auplc-localinference:latest}"
NAME="${NAME:-auplc-li}"
PORT="${PORT:-8888}"
TOKEN="${TOKEN:-auplc}"

docker rm -f "$NAME" >/dev/null 2>&1 || true

# jovyan is non-root, so it needs the host's render/video GIDs to open
# /dev/kfd and /dev/dri.
docker run -d --name "$NAME" \
  --device /dev/kfd --device /dev/dri \
  --group-add "$(getent group render | cut -d: -f3)" \
  --group-add "$(getent group video | cut -d: -f3)" \
  --security-opt seccomp=unconfined \
  --shm-size 16g \
  -p "${PORT}:8888" \
  -e JUPYTER_TOKEN="$TOKEN" \
  "$IMAGE" \
  bash -c 'source /opt/ros/$ROS_DISTRO/setup.bash &&
           source /ryzers/rai/install/setup.bash &&
           export USER=jovyan SHELL=/bin/bash &&
           exec python3 -m jupyterlab --ip=0.0.0.0 --port=8888 --no-browser'
