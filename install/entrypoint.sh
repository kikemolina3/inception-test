#!/bin/bash
set -e

# DinD bootstrap: start dockerd, then exec inception.sh

dockerd --storage-driver=vfs &>/var/log/dockerd.log &
for i in $(seq 1 30); do
    docker info &>/dev/null && break
    [ "$i" -eq 30 ] && { cat /var/log/dockerd.log; exit 1; }
    sleep 1
done

cd /workspace/install
exec bash inception.sh "$@"
