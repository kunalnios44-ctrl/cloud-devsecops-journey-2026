#!/bin/bash
set -e

docker network create ha-net
docker build -t nordic-api:v2 .
docker run -d --name backend-1 --hostname server-1 --network ha-net nordic-api:v2
docker run -d --name backend-2 --hostname server-2 --network ha-net nordic-api:v2
docker run -d --name load-balancer --network ha-net -p 80:80 -v $(pwd)/nginx.conf:/etc/nginx/nginx.conf:ro nginx:alpine
docker ps
