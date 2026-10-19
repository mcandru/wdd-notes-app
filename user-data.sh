#!/usr/bin/env bash
#
# Runs once, on the instance, the first time it boots.
#
# The image is public, so the instance can pull it without logging in to a
# registry. The app has no settings, so it keeps notes in memory and writes
# uploaded files to the container's disk.

set -e

IMAGE="ghcr.io/mcandru/wdd-notes-app:custom-domain"

dnf install -y docker
systemctl enable --now docker

# -p 80:8000 publishes the container's port 8000 as port 80 on the machine.
docker run -d \
  --name notes \
  --restart unless-stopped \
  -p 80:8000 \
  "$IMAGE"
