#!/bin/bash

set -e
set -x

pushd / || exit 1
echo "decompressing rootfs..."
sudo tar -xvf /tmp/rootfs.tar
popd

pushd /tmp || exit 1
echo "running setup script..."
chmod +x setup.sh
sudo ./setup.sh
