FROM caddy:2 AS caddy

FROM debian:bookworm-slim

ARG NODE_VERSION=24.22.1
ARG PNPM_VERSION=11.7.0
# 安装到镜像里的 dsh 版本,CI 构建时会传入具体的发布版本号
ARG DSH_VERSION=latest
# 可选镜像源,默认使用官方源;国内本地构建可传入
# APT_MIRROR=mirrors.ustc.edu.cn  NODE_MIRROR=https://npmmirror.com/mirrors/node
ARG APT_MIRROR=
ARG NODE_MIRROR=https://nodejs.org/dist

LABEL org.opencontainers.image.title="DeepSeek Harness (HTTP)" \
      org.opencontainers.image.description="DeepSeek Harness web UI over plain HTTP with optional basic auth"

# 1. (可选)替换 apt 源并安装系统依赖 (含 xz-utils 用于解压 node tarball)
# 2. 下载 Node 官方二进制包,校验 SHA256 后解压到 /usr/local
# 3. 创建 node (1000, 可登录 shell) 和 caddy (1001, 不可登录) 用户/组
RUN set -e && \
    if [ -n "${APT_MIRROR}" ] && [ -f /etc/apt/sources.list.d/debian.sources ]; then \
      sed -i "s/deb.debian.org/${APT_MIRROR}/g" /etc/apt/sources.list.d/debian.sources; \
    fi && \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      bash bubblewrap ca-certificates curl git gosu openssh-client ripgrep tini xz-utils && \
    rm -rf /var/lib/apt/lists/* && \
    ARCH="$(dpkg --print-architecture)" && \
    case "${ARCH}" in \
      amd64) NODE_ARCH="x64" ;; \
      arm64) NODE_ARCH="arm64" ;; \
      armhf) NODE_ARCH="armv7l" ;; \
      *) echo "Unsupported architecture: ${ARCH}" && exit 1 ;; \
    esac && \
    NODE_TARBALL="node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz" && \
    cd /tmp && \
    curl -fsSLO "${NODE_MIRROR}/v${NODE_VERSION}/${NODE_TARBALL}" && \
    curl -fsSLO "${NODE_MIRROR}/v${NODE_VERSION}/SHASUMS256.txt" && \
    grep " ${NODE_TARBALL}\$" SHASUMS256.txt | sha256sum -c - && \
    tar -xJf "${NODE_TARBALL}" --strip-components=1 --no-same-owner -C /usr/local && \
    rm -f "${NODE_TARBALL}" SHASUMS256.txt \
      /usr/local/CHANGELOG.md /usr/local/LICENSE /usr/local/README.md && \
    cd / && \
    groupadd --gid 1000 node && \
    useradd --uid 1000 --gid node --shell /bin/bash --home-dir /data/dsh/home node && \
    groupadd --system --gid 1001 caddy && \
    useradd --system --uid 1001 --gid caddy --home-dir /var/lib/caddy \
      --create-home --shell /usr/sbin/nologin caddy

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
    install -d -m 0700 -o node -g node /data/dsh /data/dsh/home && \
    install -d -m 0750 -o node -g node /data/dsh/home/workspace && \
    install -d -m 0700 -o caddy -g caddy /data/caddy /data/caddy/config && \
    dsh --help >/dev/null && \
    grep -h '"version"' /opt/dsh/node_modules/@deepseek-ai/dsh/package.json

# DSH_WORKSPACE 为默认工作目录,可在运行时通过环境变量覆盖(由入口脚本 cd 进入)
ENV DSH_HOME=/data/dsh \
    SHELL=/bin/bash \
    DSH_WORKSPACE=/data/dsh/home/workspace \
    DSH_TELEMETRY_DISABLED=1 \
    PORT=8080

WORKDIR /data/dsh/home/workspace
VOLUME ["/data"]
EXPOSE 8080

# 直接检查回环地址上的 dsh,无论是否启用 basic auth 都适用
HEALTHCHECK --interval=30s --timeout=5s --start-period=240s --retries=3 \
  CMD curl -fsS --max-time 5 http://127.0.0.1:3080/ >/dev/null || exit 1

STOPSIGNAL SIGTERM
ENTRYPOINT ["tini", "--", "/usr/local/bin/docker-entrypoint.sh"]
