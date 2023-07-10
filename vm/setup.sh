#!/bin/bash

set -e

export DEBIAN_FRONTEND=noninteractive

RUNNER_USER="runner"
RUNNER_DIR="/home/${RUNNER_USER}"
RUNNER_VER=2.305.0

HELM_VERSION=3.12.1

DOCKER_USER_UID=33333
DOCKER_GROUP_GID=33333

DOCKER_VERSION=20.10.23
DOCKER_COMPOSE_VERSION=v2.16.0
DOCKER_BUILDX_VERSION=0.11.1

groupadd docker --gid $DOCKER_GROUP_GID
adduser --disabled-password --gecos "" --uid $DOCKER_USER_UID --gid $DOCKER_GROUP_GID ${RUNNER_USER}
usermod -aG sudo ${RUNNER_USER}
usermod -aG docker ${RUNNER_USER}
echo "%sudo   ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers
echo "Defaults env_keep += \"DEBIAN_FRONTEND\"" >> /etc/sudoers
echo "✅ User ${RUNNER_USER} successfully created"

apt-get update
apt-get install -y \
	ca-certificates \
	curl \
	gnupg

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
	"deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null

apt-get update

# remove snapd
apt remove -y --autoremove snapd
cat <<-EOF >/etc/apt/preferences.d/nosnap.pref
	Package: snapd
	Pin: release a=*
	Pin-Priority: -10
EOF

apt-get dist-upgrade -y
apt-get install -y \
	containerd.io \
	apt-transport-https ca-certificates curl gnupg2 software-properties-common \
	iptables libseccomp2 conntrack ipset \
	jq \
	iproute2 \
	auditd \
	ethtool \
	net-tools \
	google-compute-engine \
	dkms \
	chrony \
	libblockdev-mdraid2 \
	pigz socat \
	xz-utils \
	zstd \
	xfsprogs \
	coreutils \
	atop iftop sysstat iotop fio \
	tshark \
	python3-pip \
	cgroup-tools \
	linux-tools-common linux-headers-generic linux-tools-generic linux-virtual \
	dkms \
	smem \
	linux-base \
	unzip \
	libyaml-dev

curl -fLo docker.tgz https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz \
    && tar zxvf docker.tgz \
	&& rm docker/containerd \
	&& cp docker/* /usr/bin/ \
	&& rm -rf docker docker.tgz

mkdir -p /usr/libexec/docker/cli-plugins \
&& curl -fLo /usr/libexec/docker/cli-plugins/docker-compose https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64 \
&& chmod +x /usr/libexec/docker/cli-plugins/docker-compose \
&& ln -s /usr/libexec/docker/cli-plugins/docker-compose /usr/bin/docker-compose \
&& docker compose version \
&& curl -fLo /usr/libexec/docker/cli-plugins/docker-buildx https://github.com/docker/buildx/releases/download/v${DOCKER_BUILDX_VERSION}/buildx-v${DOCKER_BUILDX_VERSION}.linux-amd64 \
&& chmod +x /usr/libexec/docker/cli-plugins/docker-buildx \
&& ln -s /usr/libexec/docker/cli-plugins/docker-buildx /usr/bin/docker-buildx


cat <<EOF > /lib/systemd/system/docker.service
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target docker.socket firewalld.service containerd.service time-set.target
Wants=network-online.target containerd.service
Requires=docker.socket

[Service]
Type=notify
# the default is not to use systemd for cgroups because the delegate issues still
# exists and systemd currently does not support the cgroup feature set required
# for containers run by docker
ExecStart=/usr/bin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock
ExecReload=/bin/kill -s HUP $MAINPID
TimeoutStartSec=0
RestartSec=2
Restart=always

# Note that StartLimit* options were moved from "Service" to "Unit" in systemd 229.
# Both the old, and new location are accepted by systemd 229 and up, so using the old location
# to make them work for either version of systemd.
StartLimitBurst=3

# Note that StartLimitInterval was renamed to StartLimitIntervalSec in systemd 230.
# Both the old, and new name are accepted by systemd 230 and up, so using the old name to make
# this option work for either version of systemd.
StartLimitInterval=60s

# Having non-zero Limit*s causes performance problems due to accounting overhead
# in the kernel. We recommend using cgroups to do container-local accounting.
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity

# Comment TasksMax if your systemd version does not support it.
# Only systemd 226 and above support this option.
TasksMax=infinity

# set delegate yes so that systemd does not reset the cgroups of docker containers
Delegate=yes

# kill only the docker process, not all processes in the cgroup
KillMode=process
OOMScoreAdjust=-500

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > /lib/systemd/system/docker.socket
[Unit]
Description=Docker Socket for the API

[Socket]
# If /var/run is not implemented as a symlink to /run, you may need to
# specify ListenStream=/var/run/docker.sock instead.
ListenStream=/run/docker.sock
SocketMode=0660
SocketUser=root
SocketGroup=docker

[Install]
WantedBy=sockets.target
EOF

mkdir -p /etc/docker
cat <<EOF > /etc/docker/daemon.json
{
  "mtu": 1440,
  "builder": {
    "gc": {
      "defaultKeepStorage": "20GB",
      "enabled": true
    }
  },
  "experimental": true
}
EOF

systemctl daemon-reload
systemctl enable docker.socket
systemctl enable docker.service --now || (journalctl -xeu docker.service && exit 1)

echo "✅ User ${RUNNER_USER} successfully added to Docker group"

# Download k3s install script
curl -sSL https://get.k3s.io/ -o /usr/local/bin/install-k3s.sh
chmod +x /usr/local/bin/install-k3s.sh

# Install helm
curl -fsSL https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz -o - | tar -xzvC /tmp/ --strip-components=1
cp /tmp/helm /usr/local/bin/helm

# Install yq (YAML processor)
curl -fsSL https://github.com/mikefarah/yq/releases/download/v4.22.1/yq_linux_amd64 -o /usr/local/bin/yq
chmod +x /usr/local/bin/yq

# Install oci-tool
curl -fsSL https://github.com/csweichel/oci-tool/releases/download/v0.2.0/oci-tool_0.2.0_linux_amd64.tar.gz | tar xz -C /usr/local/bin
chmod +x /usr/local/bin/oci-tool

echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
apt-get update
apt-get install -y google-cloud-cli

# Install actions-runner
mkdir /actions-runner
pushd /actions-runner || exit 1
curl -o actions-runner-linux-x64-${RUNNER_VER}.tar.gz -L https://github.com/actions/runner/releases/download/v${RUNNER_VER}/actions-runner-linux-x64-${RUNNER_VER}.tar.gz
tar xzf ./actions-runner-linux-x64-${RUNNER_VER}.tar.gz
chown -R ${RUNNER_USER} /actions-runner
./bin/installdependencies.sh
echo '✅ actions-runner successfully installed'
popd || exit 1

# leeway
LEEWAY_MAX_PROVENANCE_BUNDLE_SIZE=8388608
LEEWAY_CACHE_DIR=/var/tmp/cache
LEEWAY_BUILD_DIR=/var/tmp/build
LEEWAY_VERSION="0.7.4"

mkdir -p "${LEEWAY_CACHE_DIR}" "${LEEWAY_BUILD_DIR}"
chmod 777 -R /var/tmp/

curl -fsSL https://github.com/gitpod-io/leeway/releases/download/v${LEEWAY_VERSION}/leeway_${LEEWAY_VERSION}_Linux_x86_64.tar.gz | tar xz

# aws cli
curl -sfSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" &&
	unzip -qo awscliv2.zip &&
	./aws/install --update &&
	rm -rf aws awscliv2.zip

# setup runner user
cat <<-'EOF' >/tmp/runner.sh
	#!/bin/bash

	set -e

	# go
	GO_VERSION=1.20.5
	GOPATH=/home/runner/go-packages
	GOROOT=/home/runner/go
	PATH=$GOROOT/bin:$GOPATH/bin:$PATH

	cd /home/runner

	curl -fsSL https://dl.google.com/go/go$GO_VERSION.linux-amd64.tar.gz | tar xzs
	# install VS Code Go tools for use with gopls as per https://github.com/golang/vscode-go/blob/master/docs/tools.md
	# also https://github.com/golang/vscode-go/blob/27bbf42a1523cadb19fad21e0f9d7c316b625684/src/goTools.ts#L139
	go install -v github.com/uudashr/gopkgs/cmd/gopkgs@v2 \
	&& go install -v github.com/ramya-rao-a/go-outline@latest \
	&& go install -v github.com/cweill/gotests/gotests@latest \
	&& go install -v github.com/fatih/gomodifytags@latest \
	&& go install -v github.com/josharian/impl@latest \
	&& go install -v github.com/haya14busa/goplay/cmd/goplay@latest \
	&& go install -v github.com/go-delve/delve/cmd/dlv@latest \
	&& go install -v github.com/golangci/golangci-lint/cmd/golangci-lint@latest \
	&& go install -v golang.org/x/tools/gopls@latest \
	&& go install -v honnef.co/go/tools/cmd/staticcheck@latest \
	&& go install -v sigs.k8s.io/controller-runtime/tools/setup-envtest@latest

	# Install kubebuilder
	sudo $(which setup-envtest) use 1.26.1 --bin-dir /usr/local/bin/

	# Pull required images
	docker pull eu.gcr.io/gitpod-core-dev/dev/dev-environment:cw-bump-leeway-075-gha.12686
	docker pull eu.gcr.io/gitpod-core-dev/dev/dev-environment:aledbf-new-dev-image-gha.12771
	docker pull gitpod/workspace-full
	docker pull mysql:5.7
EOF

chmod +x /tmp/runner.sh

su -c /tmp/runner.sh runner

echo '✅ setup script for user ${RUNNER_USER} executed'

KUBEBUILDER_ASSETS=/usr/local/bin/k8s/1.26.1-linux-amd64

# Customize the runner variables
echo PATH=$PATH >>/${RUNNER_DIR}/.bashrc
echo KUBEBUILDER_ASSETS=$KUBEBUILDER_ASSETS >>/${RUNNER_DIR}/.bashrc
echo '✅ .bashrc for user ${RUNNER_USER} updated'

cat <<-EOF >/actions-runner/wait-for-config.sh
	#!/bin/bash
	set -e

	while ! [ -f /.github-runner-config-ready ];do
	   echo -n '#'
	   sleep 1
	done

	/actions-runner/run.sh
EOF

cat <<-EOF >/etc/systemd/system/github-runner.service
	[Unit]
	Description=Connect self hosted runner (to Github)
	Wants=network-online.target
	After=network.target network-online.target docker.service

	StartLimitIntervalSec=500
	StartLimitBurst=5

	[Service]
	Type=simple
	User=runner
	Group=docker
	ExecStart=/actions-runner/wait-for-config.sh
	TimeoutStartSec=0
	Restart=on-failure
	RestartSec=5s

	[Install]
	WantedBy=default.target
EOF

chmod +x /actions-runner/wait-for-config.sh

systemctl daemon-reload
systemctl enable github-runner

cat <<-EOF >/etc/systemd/system/destroy-vm.service
	[Unit]
	Description="Systemd service that invokes the script that destroys a VM"

	[Service]
	ExecStart=/etc/systemd/system/shutdown.sh
EOF

cat <<-EOF >/etc/systemd/system/destroy-vm.timer
	[Unit]
	Description="Run destroy-vm.service 1d after boot relative to activation time"

	[Timer]
	OnBootSec=2h
	Unit=destroy-vm.service

	[Install]
	WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable destroy-vm.timer

# cleanup
echo "Removing old packages..."
apt update
apt autoremove --purge --assume-yes

echo "Removing netplan network scripts..."
rm -rf /etc/netplan/*

echo "Removing cloud-init configuration..."
cloud-init clean --logs --seed

echo "Changing SSH port to 2222"
cat <<EOF >/etc/ssh/sshd_config.d/gitpod.conf
Port 2222
EOF

echo "Cleanup..."
rm /etc/hostname

# cleanup temporal packages
apt-get clean --assume-yes --quiet
apt-get autoclean --assume-yes --quiet
apt-get autoremove --assume-yes --quiet

# Disable services that can impact the VM during start. This is discouraged in everyday
# situations, but by using the cluster autoscaler the node rotation removes any benefit.
SERVICES_TO_DISABLE=(
	apt-daily-upgrade.timer
	apt-daily.timer
	apt-daily-upgrade.service
	apt-daily.service
	man-db.timer
	man-db.service
	crond.service
	motd-news.service
	motd-news.timer
	unattended-upgrades.service
	apport.service
	apport-autoreport.service
	bluetooth.target
	ua-messaging.service
	ua-messaging.timer
	ua-timer.timer
	ua-timer.service
	ubuntu-advantage.service
	secureboot-db.service
	atop.service
)
# shellcheck disable=SC2048
for SERVICE in ${SERVICES_TO_DISABLE[*]}; do
	systemctl stop "${SERVICE}" || true
	systemctl disable "${SERVICE}" || true
done

# Avoid DNS issues configuring the metadata host
echo "169.254.169.254 metadata.google.internal" >>/etc/hosts

# remove temporal files
rm -rf /tmp/*

sed -i 's/GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="fsck.mode=skip \1"/g' /etc/default/grub
update-grub

echo "Rotating journalctl logs"
rm -rf /var/log/journal/*
journalctl --rotate
journalctl --vacuum-time=1s

# ensure the first boot does not check the disk
touch /fastboot
