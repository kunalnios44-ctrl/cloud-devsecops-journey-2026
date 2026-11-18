#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
NETWORK_NAME="nordic-nexus-demo"
IMAGE_NAME="nordic-nexus-demo:local"
HTTP_PORT="${HTTP_PORT:-8080}"

command -v docker >/dev/null 2>&1 || {
  printf '[ERROR] Docker is required.\n' >&2
  exit 1
}

docker network inspect "$NETWORK_NAME" >/dev/null 2>&1 ||
  docker network create "$NETWORK_NAME" >/dev/null

# Re-running the script replaces only its own named demo containers.
docker rm -f backend-1 backend-2 load-balancer >/dev/null 2>&1 || true

docker build --pull --file "$SCRIPT_DIR/Dockerfile" --tag "$IMAGE_NAME" "$SCRIPT_DIR"

docker run --detach --restart unless-stopped \
  --name backend-1 --hostname server-1 --network "$NETWORK_NAME" "$IMAGE_NAME"

docker run --detach --restart unless-stopped \
  --name backend-2 --hostname server-2 --network "$NETWORK_NAME" "$IMAGE_NAME"

docker run --detach --restart unless-stopped \
  --name load-balancer --network "$NETWORK_NAME" \
  --publish "${HTTP_PORT}:8080" \
  --volume "$SCRIPT_DIR/nginx.conf:/etc/nginx/nginx.conf:ro" \
  nginxinc/nginx-unprivileged:1.27-alpine

docker ps --filter "network=$NETWORK_NAME"
