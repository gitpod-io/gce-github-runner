#!/bin/bash

set -e
set -x

pushd /tmp || exit 1
echo "decompressing rootfs..."
tar -xvf /tmp/rootfs.tar
sudo cp -Rvn rootfs/* /

echo "running setup script..."
chmod +x setup.sh
sudo ./setup.sh
popd
