
FROM eu.gcr.io/gitpod-core-dev/dev/dev-environment:base

# leeway
ARG LEEWAY_VERSION=0.7.6
ENV LEEWAY_MAX_PROVENANCE_BUNDLE_SIZE=8388608
ENV LEEWAY_CACHE_DIR=/var/tmp/cache
ENV LEEWAY_BUILD_DIR=/var/tmp/build

RUN cd /usr/bin && curl -fsSL https://github.com/gitpod-io/leeway/releases/download/v${LEEWAY_VERSION}/leeway_${LEEWAY_VERSION}_Linux_x86_64.tar.gz | sudo tar xz

RUN cd /usr/bin && sudo curl -fsSL https://github.com/mikefarah/yq/releases/download/v4.23.1/yq_linux_amd64 > yq \
    && sudo chmod +x yq

### Google Cloud ###
# not installed via repository as then 'docker-credential-gcr' is not available
ARG GCS_DIR=/opt/google-cloud-sdk
ENV PATH=$GCS_DIR/bin:$PATH
RUN sudo chown gitpod: /opt \
    && mkdir $GCS_DIR \
    && curl -fsSL https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-420.0.0-linux-x86_64.tar.gz \
    | tar -xzvC /opt \
    && /opt/google-cloud-sdk/install.sh --quiet --usage-reporting=false --bash-completion=true \
    --additional-components gke-gcloud-auth-plugin docker-credential-gcr alpha beta \
    # needed for access to our private registries
    && docker-credential-gcr configure-docker

RUN sudo python3 -m pip uninstall crcmod; sudo python3 -m pip install --no-cache-dir -U crcmod

### gitpod-core specific gcloud config
# Copy GCloud default config that points to gitpod-dev
ARG GCLOUD_CONFIG_DIR=/home/gitpod/.config/gcloud
COPY --chown=gitpod gcloud-default-config $GCLOUD_CONFIG_DIR/configurations/config_default

# Install pre-commit https://pre-commit.com/#install
RUN sudo install-packages shellcheck \
    && sudo python3 -m pip install pre-commit
