
FROM eu.gcr.io/gitpod-core-dev/dev/dev-environment:base

# leeway
ARG LEEWAY_VERSION=0.8.4
ENV LEEWAY_MAX_PROVENANCE_BUNDLE_SIZE=8388608
ENV LEEWAY_CACHE_DIR=/var/tmp/cache
ENV LEEWAY_BUILD_DIR=/var/tmp/build

RUN cd /usr/bin && curl -fsSL https://github.com/gitpod-io/leeway/releases/download/v${LEEWAY_VERSION}/leeway_${LEEWAY_VERSION}_Linux_x86_64.tar.gz | sudo tar xz

RUN cd /usr/bin && curl -fsSL https://github.com/mikefarah/yq/releases/download/v4.35.2/yq_linux_amd64 | sudo tee -a yq >/dev/null 2>&1 \
    && sudo chmod +x yq

### Google Cloud ###
# not installed via repository as then 'docker-credential-gcr' is not available
ARG GCS_DIR=/opt/google-cloud-sdk
ENV PATH=$GCS_DIR/bin:$PATH
RUN sudo chown gitpod: /opt \
    && mkdir $GCS_DIR \
    && curl -fsSL https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-445.0.0-linux-x86_64.tar.gz \
    | tar -xzvC /opt \
    && /opt/google-cloud-sdk/install.sh --quiet --usage-reporting=false --bash-completion=true \
    --additional-components gke-gcloud-auth-plugin docker-credential-gcr alpha beta \
    # needed for access to our private registries
    && docker-credential-gcr configure-docker

RUN sudo install-packages python3-pip

RUN sudo python3 -m pip uninstall crcmod \
    && sudo python3 -m pip install --no-cache-dir -U crcmod

# Install pre-commit https://pre-commit.com/#install
RUN sudo install-packages shellcheck \
    && sudo python3 -m pip install pre-commit

RUN wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list \
    && sudo install-packages packer
