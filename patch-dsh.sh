#!/usr/bin/env bash
# 设置 DSH_AUTH_PROXY=1 时跳过 dsh 的启动 token / cookie 校验(思路与 1Panel 镜像相同)
# 用法:patch-dsh.sh <npm 安装目录>
# 如果上游源码结构变了、找不到目标代码,会直接报错退出,避免产出未打补丁的镜像
set -Eeuo pipefail

prefix="${1:?usage: patch-dsh.sh <npm-prefix>}"
marker='DSH_AUTH_PROXY'
patched=0

while IFS= read -r -d '' file; do
  if grep -q "$marker" "$file"; then
    patched=$((patched + 1))
    continue
  fi
  sed -i -E 's/^([[:space:]]*isAuthenticated\(request, secure = false\) \{)$/\1\n\t\tif (process.env.DSH_AUTH_PROXY === "1") return true;/' "$file"
  if ! grep -q "$marker" "$file"; then
    printf 'patch-dsh: isAuthenticated() not found in %s\n' "$file" >&2
    exit 1
  fi
  patched=$((patched + 1))
done < <(find "$prefix" -path '*dsh-client-connection/lib/index.js' -type f -print0)

if (( patched == 0 )); then
  printf 'patch-dsh: dsh-client-connection not found under %s\n' "$prefix" >&2
  exit 1
fi
printf 'patch-dsh: patched %d file(s) under %s\n' "$patched" "$prefix"
