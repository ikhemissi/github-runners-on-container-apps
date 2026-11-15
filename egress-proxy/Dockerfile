# The runners' egress proxy: Canonical's Squid image (Ubuntu 24.04 LTS) with this folder's configuration and allowlist.
# The base image's entrypoint runs Squid in the foreground and copies its logs to the container's output.
FROM ubuntu/squid:6.6-24.04_edge@sha256:8a3baed477e2c282ab8aa5edad442f69873246964f225c5c2ae8364b6610963c

COPY squid.conf allowlist.txt /etc/squid/

EXPOSE 3128
