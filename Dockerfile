ARG TARGETARCH

ARG UV_VERSION=0.12.4
ARG JQ_VERSION=1.8.2
ARG PYTHON_VERSION=3.12
ARG PNPM_VERSION=11
ARG NVM_VERSION=0.40.6
ARG TF_VERSION=1.15.8
ARG KUBECTL_VERSION=v1.36.3
ARG HELM_VERSION=4.2.4
ARG SCOUT_VERSION=1.24.0
ARG DATABRICKS_CLI_VERSION=1.9.0

FROM ghcr.io/astral-sh/uv:${UV_VERSION} AS uv-binaries

FROM debian:bookworm-slim

ARG TARGETARCH
ARG JQ_VERSION
ARG PYTHON_VERSION
ARG PNPM_VERSION
ARG NVM_VERSION
ARG TF_VERSION
ARG KUBECTL_VERSION
ARG HELM_VERSION
ARG SCOUT_VERSION
ARG DATABRICKS_CLI_VERSION

LABEL org.opencontainers.image.source="https://github.com/TaeHyungKim90/cloud-ops-builder"
LABEL org.opencontainers.image.title="Cloud Ops Builder"
LABEL org.opencontainers.image.description="A tool to build and deploy cloud operations tools."
LABEL org.opencontainers.image.licenses="Apache-2.0"

ENV DEBIAN_FRONTEND=noninteractive

RUN echo "Building for architecture: ${TARGETARCH}"

# 1. Install essential system tools
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    unzip \
    git \
    xz-utils \
    gnupg \
    make \
    && rm -rf /var/lib/apt/lists/*

# 2. Node.js v24 (Manual binary install for multi-arch precision)
RUN curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" -o /tmp/install-nvm.sh && \
    bash /tmp/install-nvm.sh && \
    rm -f /tmp/install-nvm.sh && \
    export NVM_DIR="$HOME/.nvm" && \
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" && \
    nvm install 24 && \
    nvm use 24 && \
    nvm alias 24 && \
    ln -sf $(which node) /usr/local/bin/node && \
    ln -sf $(which npm) /usr/local/bin/npm && \
    ln -sf $(which npx) /usr/local/bin/npx && \
    ln -sf $(which corepack) /usr/local/bin/corepack && \
    corepack enable && \
    corepack prepare pnpm@${PNPM_VERSION} --activate && \
    ln -sf $(which pnpm) /usr/local/bin/pnpm && \
    node -v && npm -v && corepack --version && pnpm -v

# 3. Install AWS CLI v2
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install -i /usr/local/aws-cli -b /usr/local/bin && \
    rm -rf awscliv2.zip aws && \
    aws --version

# 4. Install kubectl
RUN curl -fsSLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" && \
    curl -fsSLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl.sha256" && \
    echo "$(cat kubectl.sha256)  kubectl" | sha256sum -c - && \
    mv kubectl /usr/local/bin/ && \
    rm -f kubectl.sha256 && \
    chmod +x /usr/local/bin/kubectl && \
    kubectl version --client

# 5. Install Helm
RUN curl -fsSL "https://raw.githubusercontent.com/helm/helm/v${HELM_VERSION}/scripts/get-helm-4" -o /tmp/get-helm-4.sh && \
    chmod +x /tmp/get-helm-4.sh && \
    DESIRED_VERSION="v${HELM_VERSION}" /tmp/get-helm-4.sh && \
    rm -f /tmp/get-helm-4.sh && \
    helm version --short

# 6. Install uv
COPY --from=uv-binaries /uv /uvx /bin/
RUN uv python install ${PYTHON_VERSION} && \
    PYTHON_PATH=$(uv python find ${PYTHON_VERSION}) && \
    ln -sf "$PYTHON_PATH" /usr/local/bin/python${PYTHON_VERSION} && \
    ln -sf "$PYTHON_PATH" /usr/local/bin/python3 && \
    ln -sf "$PYTHON_PATH" /usr/local/bin/python

ENV UV_LINK_MODE=copy \
    UV_COMPILE_BYTECODE=1 \
    PYTHONUNBUFFERED=1

# 7. Install Docker CLI and Docker Compose
RUN install -m 0755 -d /etc/apt/keyrings
RUN curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
RUN chmod a+r /etc/apt/keyrings/docker.asc
RUN echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian bookworm stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

RUN apt-get update && apt-get install -y --no-install-recommends docker-ce-cli && rm -rf /var/lib/apt/lists/*

# 8. Install jq
RUN curl -fsSL "https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-${TARGETARCH}" -o jq-linux-${TARGETARCH} && \
    curl -fsSL "https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/sha256sum.txt" -o jq-sha256sum.txt && \
    grep " jq-linux-${TARGETARCH}$" jq-sha256sum.txt | sha256sum -c - && \
    mv jq-linux-${TARGETARCH} /usr/local/bin/jq && \
    rm -f jq-sha256sum.txt && \
    chmod +x /usr/local/bin/jq && \
    jq --version

# 9. Install databricks-cli
RUN curl -fsSL https://raw.githubusercontent.com/databricks/setup-cli/v${DATABRICKS_CLI_VERSION}/install.sh | bash && \
    databricks --version

# 10. Install Terraform
RUN curl -LO "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_${TARGETARCH}.zip" && \
    curl -fsSLO "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_SHA256SUMS" && \
    grep " terraform_${TF_VERSION}_linux_${TARGETARCH}.zip$" terraform_${TF_VERSION}_SHA256SUMS | sha256sum -c - && \
    unzip terraform_${TF_VERSION}_linux_${TARGETARCH}.zip -d terraform && \
    mv terraform/terraform /usr/local/bin/ && \
    rm terraform_${TF_VERSION}_linux_${TARGETARCH}.zip && \
    rm terraform_${TF_VERSION}_SHA256SUMS && \
    rm -rf terraform && \
    terraform version

# 11. Install docker-scout
RUN mkdir -p /usr/local/lib/docker/cli-plugins && \
    curl -fsSL "https://github.com/docker/scout-cli/releases/download/v${SCOUT_VERSION}/docker-scout_${SCOUT_VERSION}_linux_${TARGETARCH}.tar.gz" | \
    tar -xz -C /usr/local/lib/docker/cli-plugins docker-scout && \
    chmod +x /usr/local/lib/docker/cli-plugins/docker-scout && \
    docker scout version

# 12. Install Grype
RUN curl -fsSLO "https://raw.githubusercontent.com/anchore/grype/main/install.sh" && \
    chmod +x install.sh && \
    ./install.sh -b /usr/local/bin && \
    rm install.sh && \
    grype version

WORKDIR /app
