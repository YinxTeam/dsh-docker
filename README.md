# DeepSeek Harness (plain HTTP)

自建的 DeepSeek Harness (`@deepseek-ai/dsh`) 镜像:明文 HTTP、无需 token、可选 basic auth、可全网访问。

## Docker 部署

镜像:`ghcr.io/yinxteam/dsh-docker:latest`(支持 amd64 / arm64)。

### 方式一:docker compose(推荐)

```bash
# 可选:从示例复制 .env 并修改认证和端口(不创建则无认证,端口 8080)
cp .env.example .env

docker compose up -d
```

浏览器打开 `http://<服务器IP>:8080`。工作区默认在容器内 `/data/dsh/home/workspace`,与 dsh 的设置、会话数据一起保存在命名卷 `dsh-data`。

### 方式二:docker run

```bash
docker run -d --name deepseek-harness --restart unless-stopped \
  -p 8080:8080 \
  -e DSH_AUTH_USERNAME=admin -e DSH_AUTH_PASSWORD='请改成强密码' \
  -v dsh-data:/data/dsh \
  ghcr.io/yinxteam/dsh-docker:latest
```

不需要认证时,去掉两个 `DSH_AUTH_*` 参数即可。

### 本地构建

```bash
docker compose build
DSH_IMAGE=deepseek-harness:local docker compose up -d
```

### 配置项

| 环境变量 | 默认 | 说明 |
| --- | --- | --- |
| `PORT` | `8080` | 容器内外监听端口(需 ≥1024) |
| `DSH_AUTH_USERNAME` / `DSH_AUTH_PASSWORD` | 空 | 同时设置则启用 basic auth;同时留空则不认证;只设一个会启动失败 |
| `DSH_WORKSPACE` | `/data/dsh/home/workspace` | 默认工作目录(绝对路径,启动时自动创建并 cd 进入);改到卷外时需自行挂载该路径 |

## 更新 dsh

dsh 的版本在镜像构建时确定,容器内不再联网更新。GitHub Actions(`.github/workflows/build.yml`)每天查询 npm 上 `@deepseek-ai/dsh` 的 `latest`,GHCR 里还没有对应版本号的镜像就自动构建:先做冒烟测试(`tests/smoke.sh`),通过后推送 `amd64`/`arm64` 镜像,标签为具体版本号和 `latest`。每周一还会强制重建一次,以获得基础镜像更新。也可以在 Actions 页面手动触发。

使用方更新容器:

```bash
docker compose pull && docker compose up -d
# docker run 用户:重新 pull 后删除旧容器再运行
```

固定版本就把 `DSH_IMAGE` 的标签改成具体版本号(如 `ghcr.io/yinxteam/dsh-docker:0.2.1-rc.2`)。本地自行构建:`docker compose build --build-arg DSH_VERSION=<版本>`。

## 实现说明

- `dsh` 只监听容器内 `127.0.0.1:3080`,Caddy 在 `:PORT` 提供 HTTP、压缩、可选 basic auth。
- 免 token:构建/安装 dsh 后由 `patch-dsh.sh` 给 `dsh-client-connection` 的 `isAuthenticated()` 加一行 `DSH_AUTH_PROXY=1` 时直接放行(与 1Panel 镜像同思路)。补丁没匹配到时安装失败,不会产出未打补丁的版本。
- `--trusted-host` 不支持通配符,所以 Caddy 把所有请求的 `Host` 改写为 `127.0.0.1:3080`、去掉 `Origin`;跨站写请求(`/api` 下 Origin 与当前 host 不符或 `Sec-Fetch-Site: cross-site`)由 Caddy 返回 403。

## 安全提示

不配置认证时,任何能访问该端口的人都拥有完整权限(修改设置、读写 API Key、使用终端和工作区文件)。公网部署请设置 `DSH_AUTH_USERNAME` / `DSH_AUTH_PASSWORD`,并注意 basic auth 在明文 HTTP 下可被窃听,必要时在前面再加 HTTPS 反向代理。
