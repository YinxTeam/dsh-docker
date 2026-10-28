FROM caddy:2 AS caddy

FROM node:24-bookworm-slim

ARG PNPM_VERSION=11.7.0
# dsh version installed into the image. CI passes the exact released version.
ARG DSH_VERSION=latest

LABEL org.opencontainers.image.title="DeepSeek Harness (HTTP)" \
      org.opencontainers.image.description="DeepSeek Harness web UI over plain HTTP with optional basic auth"

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      bash bubblewrap ca-certificates curl git gosu openssh-client ripgrep tini && \
    rm -rf /var/lib/apt/lists/*

COPY --from=caddy /usr/bin/caddy /usr/bin/caddy

COPY Caddyfile /etc/caddy/Caddyfile
COPY dsh /usr/local/bin/dsh
COPY patch-dsh.sh /usr/local/bin/patch-dsh.sh
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN sed -i 's/\r$//' /etc/caddy/Caddyfile /usr/local/bin/dsh /usr/local/bin/patch-dsh.sh /usr/local/bin/docker-entrypoint.sh && \
    chmod 0755 /usr/local/bin/dsh /usr/local/bin/patch-dsh.sh /usr/local/bin/docker-entrypoint.sh && \
    npm install --global "pnpm@${PNPM_VERSION}" && \
    npm cache clean --force && \
    npm install --prefix /opt/dsh "@deepseek-ai/dsh@${DSH_VERSION}" \
      --omit=dev --no-audit --no-fund && \
    patch-dsh.sh /opt/dsh && \
    groupadd --system --gid 1001 caddy && \
    useradd --system --uid 1001 --gid caddy --home-dir /var/lib/caddy \
      --create-home --shell /usr/sbin/nologin caddy && \
    install -d -m 0700 -o node -g node /data/dsh /data/dsh/home && \
    install -d -m 0750 -o node -g node /workspace && \
    install -d -m 0700 -o caddy -g caddy /data/caddy /data/caddy/config && \
    dsh --help >/dev/null && \
    grep -h '"version"' /opt/dsh/node_modules/@deepseek-ai/dsh/package.json

ENV DSH_HOME=/data/dsh \
    DSH_TELEMETRY_DISABLED=1 \
    PORT=8080

WORKDIR /workspace
VOLUME ["/data", "/workspace"]
EXPOSE 8080

# dsh answers directly on loopback, so this works with or without basic auth.
HEALTHCHECK --interval=30s --timeout=5s --start-period=240s --retries=3 \
  CMD curl -fsS --max-time 5 http://127.0.0.1:3080/ >/dev/null || exit 1

STOPSIGNAL SIGTERM
ENTRYPOINT ["tini", "--", "/usr/local/bin/docker-entrypoint.sh"]
