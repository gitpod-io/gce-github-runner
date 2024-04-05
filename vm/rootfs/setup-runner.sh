#!/bin/bash

set -e

# go
#
# If you're updating this version, please also update the version in
# gitpod-io/gitpod-dedicated as well as this ensures that we use the
# same Go version during development as we do in CI - which allows us to
# reuse the leeway cache
#
GO_VERSION=1.22.2
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
KUBEBUIDER_VERSION=1.26.1
sudo $(which setup-envtest) use "${KUBEBUIDER_VERSION}" --bin-dir /usr/local/bin/
sudo cp /usr/local/bin/k8s/${KUBEBUIDER_VERSION}-linux-amd64/* /usr/local/bin/

# Pull required images
readonly PRELOAD_FILE="/etc/preloaded-images"
if [ -f "${PRELOAD_FILE}" ]; then
	echo "Downloading container images..."
	xargs -a "${PRELOAD_FILE}" -n1 -P4 -I{} -t bash -c "docker pull --quiet {} || true"
fi
