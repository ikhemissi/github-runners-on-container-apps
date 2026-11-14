# The runner image: GitHub's official runner image, plus the Azure CLI, the GitHub CLI and Node LTS (curl, jq, openssl,
# git and Python 3 are already in it), and the entrypoint that registers one just-in-time runner and runs one job.
# Every version is pinned; downloads are checked against their published checksums or signing key.
# No Docker daemon: container actions and `services:` are not supported (docs/DECISIONS.md).
FROM ghcr.io/actions/actions-runner:2.338.2@sha256:6d0b2d80d80f143f77dcb676e50920100bbb547e39e883454d57f45ab8c31300

ARG AZURE_CLI_VERSION=2.92.0-1~noble
ARG GH_CLI_VERSION=2.104.0
ARG GH_CLI_SHA256=f90d578cbc4c3b067dfc4a1a540cef41faef64eebfb280b548ab32455977a21f
ARG NODE_VERSION=26.13.1
# Node needs libatomic, which the base image lacks.
ARG LIBATOMIC_VERSION=14.2.0-4ubuntu2~24.04.1
ARG NODE_SHA256=518674de2b621728a5e4486f5fb3b7d2900bb3cc4aa97969edaa463db99f9778
# Fingerprint of Microsoft's package signing key (packages.microsoft.com/keys/microsoft.asc).
ARG MICROSOFT_KEY_FINGERPRINT=BC528686B50D79E339D3721CEB3E94ADBE1229CF

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# root (0) to install, then back to the image's runner user (1001).
USER 0

# Azure CLI from Microsoft's repository, signed by the pinned key (gpg and ca-certificates are in the base image).
RUN export GNUPGHOME=/tmp/gnupg && mkdir -m 700 "$GNUPGHOME" \
 && curl -fsSL https://packages.microsoft.com/keys/microsoft.asc -o /tmp/microsoft.asc \
 && gpg --show-keys --with-colons /tmp/microsoft.asc | grep -q "^fpr:::::::::${MICROSOFT_KEY_FINGERPRINT}:" \
 && gpg --dearmor -o /usr/share/keyrings/microsoft.gpg /tmp/microsoft.asc \
 && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ noble main" \
      > /etc/apt/sources.list.d/azure-cli.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends "azure-cli=${AZURE_CLI_VERSION}" \
 && rm -rf /var/lib/apt/lists/* /tmp/microsoft.asc /tmp/gnupg

# GitHub CLI from its release, checked against the published checksum.
RUN curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_CLI_VERSION}/gh_${GH_CLI_VERSION}_linux_amd64.deb" -o /tmp/gh.deb \
 && echo "${GH_CLI_SHA256}  /tmp/gh.deb" | sha256sum --check --strict \
 && apt-get install -y --no-install-recommends /tmp/gh.deb \
 && rm -rf /var/lib/apt/lists/* /tmp/gh.deb

# Node LTS from nodejs.org, checked against the published checksum.
RUN apt-get update \
 && apt-get install -y --no-install-recommends "libatomic1=${LIBATOMIC_VERSION}" \
 && rm -rf /var/lib/apt/lists/* \
 && curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.gz" -o /tmp/node.tar.gz \
 && echo "${NODE_SHA256}  /tmp/node.tar.gz" | sha256sum --check --strict \
 && tar -xzf /tmp/node.tar.gz -C /usr/local --strip-components=1 --no-same-owner \
 && rm /tmp/node.tar.gz

COPY --chmod=0755 entrypoint.sh /usr/local/bin/runner-entrypoint.sh

USER 1001
ENTRYPOINT ["/usr/local/bin/runner-entrypoint.sh"]
