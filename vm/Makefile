.DEFAULT_GOAL:=help

.EXPORT_ALL_VARIABLES:

ifndef VERBOSE
.SILENT:
endif

# set default shell
SHELL=/bin/bash -o pipefail -o errexit

BUILD_ID ?= $(shell date +%Y%m%d%H%M)

# HELP
# Generate a help menu for the tasks in the Makefile
# https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
.PHONY: help

help:  ##     Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

build-actions-runner-image: ##     Builds a custom GCP image for github self-hosted runners
	packer init vm-image.pkr.hcl
	packer build -force \
		-var zone=europe-west1-b \
		-var project_id=public-github-runners \
		-var source_image=ubuntu-2204-jammy-v20230908 \
		-var image_name=gh-runner-${BUILD_ID} \
		vm-image.pkr.hcl

.PHONY: build-actions-runner-image
