#!/bin/bash

set -e

export DEBIAN_FRONTEND=noninteractive

RUNNER_USER="runner"
RUNNER_DIR="/home/${RUNNER_USER}"
RUNNER_VER=2.318.0

HELM_VERSION=3.14.0
PULUMI_VERSION=3.114.0

DOCKER_USER_UID=33333
DOCKER_GROUP_GID=33333

DOCKER_VERSION=26.1.1
DOCKER_COMPOSE_VERSION=v2.26.0
DOCKER_BUILDX_VERSION=0.14.0

echo "📝 Preparing environment for docker..."
# Only install containerd from docker.io repository to be in control of the docker services.
groupadd docker --gid $DOCKER_GROUP_GID
adduser --disabled-password --gecos "" --uid $DOCKER_USER_UID --gid $DOCKER_GROUP_GID ${RUNNER_USER}
usermod -aG sudo ${RUNNER_USER}
usermod -aG docker ${RUNNER_USER}
echo "%sudo   ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers
echo "Defaults env_keep += \"DEBIAN_FRONTEND\"" >> /etc/sudoers

apt-get update
apt-get install -y \
	ca-certificates \
	curl \
	gnupg \
	rsync

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
	"deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null

apt-get update

echo "📝 Removing snapd to avoid performance issues on boot..."
apt remove -y --autoremove snapd

echo "📝 Installing base packages required in the image..."
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

echo "📝 Installing docker, docker compose and buildx..."
curl -fLo docker.tgz https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz \
    && tar zxvf docker.tgz \
	&& rm docker/containerd \
	&& cp docker/* /usr/bin/ \
	&& rm -rf docker docker.tgz

mkdir -p /usr/libexec/docker/cli-plugins

curl -fLo /usr/libexec/docker/cli-plugins/docker-compose https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64
chmod +x /usr/libexec/docker/cli-plugins/docker-compose
ln -s /usr/libexec/docker/cli-plugins/docker-compose /usr/bin/docker-compose

curl -fLo /usr/libexec/docker/cli-plugins/docker-buildx https://github.com/docker/buildx/releases/download/v${DOCKER_BUILDX_VERSION}/buildx-v${DOCKER_BUILDX_VERSION}.linux-amd64
chmod +x /usr/libexec/docker/cli-plugins/docker-buildx
ln -s /usr/libexec/docker/cli-plugins/docker-buildx /usr/bin/docker-buildx

systemctl daemon-reload
systemctl enable docker.socket
# in case of any error starting docker, terminate the execution
systemctl enable docker.service --now || (journalctl -xeu docker.service && exit 1)

echo "📝 Downloading k3s install script..."
curl -sSL https://get.k3s.io/ -o /usr/local/bin/install-k3s.sh
chmod +x /usr/local/bin/install-k3s.sh

echo "📝 Installing helm..."
curl -fsSL https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz -o - | tar -xzvC /tmp/ --strip-components=1
cp /tmp/helm /usr/local/bin/helm

echo "📝 Installing yq (YAML processor)..."
curl -fsSL https://github.com/mikefarah/yq/releases/download/v4.35.2/yq_linux_amd64 -o /usr/local/bin/yq
chmod +x /usr/local/bin/yq

echo "📝 Installing oci-tool..."
curl -fsSL https://github.com/csweichel/oci-tool/releases/download/v0.2.0/oci-tool_0.2.0_linux_amd64.tar.gz | tar xz -C /usr/local/bin
chmod +x /usr/local/bin/oci-tool

echo "📝 Install gcloud..."
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
apt-get update
apt-get install -y google-cloud-cli

echo "📝 Installing pulumi..."
curl -fsSL https://get.pulumi.com/releases/sdk/pulumi-v${PULUMI_VERSION}-linux-x64.tar.gz | tar -xzvC /tmp/ --strip-components=1
cp /tmp/pulumi* /usr/local/bin/

echo "Installing node.js..."
export NODE_MAJOR=20
apt install -y ca-certificates curl gnupg && \
    mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" > /etc/apt/sources.list.d/nodesource.list && \
    apt-install -y nodejs && \
    npm install -g @devcontainers/cli && \
    rm -rf /usr/include/node/openssl/archs/{aix64-gcc-as,BSD-x86,BSD-x86_64,darwin64-arm64-cc,darwin64-x86_64-cc,darwin-i386-cc,linux32-s390x,linux64-loongarch64,linux64-mips64,linux64-riscv64,linux64-s390x,linux-armv4,linux-ppc64le,solaris64-x86_64-gcc,solaris-x86-gcc,VC-WIN32} && \
    rm -rf /usr/share/doc/nodejs

echo "📝 Installing actions-runner..."
RUNNER_TGZ=/tmp/actions-runner-linux-x64-${RUNNER_VER}.tar.gz

curl -o "${RUNNER_TGZ}" -L https://github.com/actions/runner/releases/download/v${RUNNER_VER}/actions-runner-linux-x64-${RUNNER_VER}.tar.gz

mkdir -p /actions-runner-1 /actions-runner-2

pushd /actions-runner-1 || exit 1
tar xzf "${RUNNER_TGZ}"
chown -R ${RUNNER_USER} /actions-runner-1
./bin/installdependencies.sh
popd || exit 1

pushd /actions-runner-2 || exit 1
curl -o actions-runner-linux-x64-${RUNNER_VER}.tar.gz -L https://github.com/actions/runner/releases/download/v${RUNNER_VER}/actions-runner-linux-x64-${RUNNER_VER}.tar.gz
tar xzf "${RUNNER_TGZ}"
chown -R ${RUNNER_USER} /actions-runner-2
./bin/installdependencies.sh
popd || exit 1

rm -f "${RUNNER_TGZ}"

echo "📝 Installing leeway..."
LEEWAY_MAX_PROVENANCE_BUNDLE_SIZE=8388608
LEEWAY_CACHE_DIR=/var/tmp/cache
LEEWAY_BUILD_DIR=/var/tmp/build
LEEWAY_VERSION="0.8.4"

mkdir -p "${LEEWAY_CACHE_DIR}" "${LEEWAY_BUILD_DIR}"
chmod 777 -R /var/tmp/

curl -fsSL https://github.com/gitpod-io/leeway/releases/download/v${LEEWAY_VERSION}/leeway_${LEEWAY_VERSION}_Linux_x86_64.tar.gz | tar -xz -C /usr/local/bin leeway

echo "📝 Installing the AWS cli..."
curl -sfSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" &&
	unzip -qo awscliv2.zip &&
	./aws/install --update &&
	rm -rf aws awscliv2.zip

echo "📝 Installing required packages for the action execution..."
su -c /setup-runner.sh runner
rm /setup-runner.sh

echo "📝 Customizing the runner variables..."
echo PATH=$PATH >>/${RUNNER_DIR}/.bashrc
echo KUBEBUILDER_ASSETS=/usr/local/bin/k8s/1.26.1-linux-amd64 >>/${RUNNER_DIR}/.bashrc

curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" |  tee /etc/apt/sources.list.d/github-cli.list > /dev/null
apt update
apt install gh -y

cat <<-EOF >/actions-runner-1/wait-for-config.sh
	#!/bin/bash
	set -e

	while ! [ -f /.github-runner-config-ready ];do
	   echo -n '#'
	   sleep 1
	done

	/actions-runner-1/run.sh
EOF

cat <<-EOF >/actions-runner-2/wait-for-config.sh
	#!/bin/bash
	set -e

	while ! [ -f /.github-runner-config-ready ];do
	   echo -n '#'
	   sleep 1
	done

	/actions-runner-2/run.sh
EOF

chmod +x /actions-runner-1/wait-for-config.sh
chmod +x /actions-runner-2/wait-for-config.sh

systemctl daemon-reload
systemctl enable github-runner-1
systemctl enable github-runner-2
systemctl enable destroy-vm.timer

echo "📝 Removing old packages..."
apt update
apt autoremove --purge --assume-yes

echo "📝 Removing netplan network scripts..."
rm -rf /etc/netplan/*

echo "📝 Removing cloud-init configuration..."
cloud-init clean --logs --seed

echo "♻️ Cleanup..."
rm /etc/hostname

# cleanup temporal packages
apt-get clean --assume-yes --quiet
apt-get autoclean --assume-yes --quiet
apt-get autoremove --assume-yes --quiet

# Disable services that can impact the VM during start. This is discouraged in everyday
# situations, but by using the cluster autoscaler the node rotation removes any benefit.
SERVICES_TO_DISABLE=(
	secureboot-db.service
    apport-autoreport.service
    apport.service
    apt-daily-upgrade.service
    apt-daily-upgrade.timer
    apt-daily.service
    apt-daily.timer
    atop.service
    atopacct.service
    autofs.service
    bluetooth.target
    console-setup.service
    crond.service
    e2scrub_reap.service
    fstrim.service
    keyboard-setup
    man-db.service
    man-db.timer
    motd-news.service
    motd-news.timer
    netplan-ovs-cleanup.service
    syslog.service
    systemd-journal-flush.service
    systemd-pcrphase.service
    ua-messaging.service
    ua-messaging.timer
    ua-reboot-cmds.service
    ua-timer.service
    ua-timer.timer
    ubuntu-advantage.service
    unattended-upgrades.service
    vgauth.service
    open-vm-tools.service
    wpa_supplicant.service
    lvm2-monitor.service
    ModemManager.service
    systemd-udev-settle.service
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

echo "📝 disabling the first boot fsck check..."
sed -i 's/GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="fsck.mode=skip \1"/g' /etc/default/grub
sed -i 's/GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="quiet loglevel=3 systemd.show_status=false rd.udev.log_level=3 libahci.ignore_sss=1 \1"/g' /etc/default/grub
sed -i 's/GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="audit=0 \1"/g' /etc/default/grub
sed -i 's/GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="rd.lvm=0 rd.luks=0 rd.md=0 rd.dm=0 rd.multipath=0 rd.iscsi=0 rd.plymouth=0 rd.udev.log_priority=3 raid=noautodetect udev.children-max=255 rd.udev.children-max=255 rd.plymouth=0 plymouth.enable=0 \1"/g' /etc/default/grub

update-grub
touch /fastboot

echo "📝 Rotating journalctl logs..."
rm -rf /var/log/journal/*
journalctl --rotate
journalctl --vacuum-time=1s

echo "tmpfs   /tmp         tmpfs   rw,nodev,nosuid,relatime          0  0" >> /etc/fstab

update-alternatives --set iptables /usr/sbin/iptables-legacy

echo "done."
