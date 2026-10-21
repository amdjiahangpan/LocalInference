#!/usr/bin/env bash
# Copyright (C) 2026 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-License-Identifier: MIT
#
# Build the LocalInference course image. The build context is this directory:
# the Dockerfile copies the notebooks and their helper directories into
# /ryzers/notebooks, and .dockerignore filters out tooling and run artifacts.
#
# Optional overrides:
#   IMAGE            tag to build (default ghcr.io/amdresearch/auplc-localinference:latest)
#   BASE_IMAGE       ROCm base image (Dockerfile default ghcr.io/amdresearch/auplc-base:latest)
#   HOST_RENDER_GID  host render group id jovyan joins (Dockerfile default 992)

set -euo pipefail

cd "$(dirname "$0")"

IMAGE="${IMAGE:-ghcr.io/amdresearch/auplc-localinference:latest}"

docker build ${BASE_IMAGE:+--build-arg BASE_IMAGE="$BASE_IMAGE"} \
  ${HOST_RENDER_GID:+--build-arg HOST_RENDER_GID="$HOST_RENDER_GID"} \
  -t "$IMAGE" .
