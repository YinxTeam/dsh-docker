#!/usr/bin/env bash
set -Eeuo pipefail

log() { printf '[entrypoint] %s\n' "$*"; }

port="${PORT:-8080}"
auth_username="${DSH_AUTH_USERNAME:-}"
auth_password="${DSH_AUTH_PASSWORD:-}"

if [[ ! "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
  printf 'PORT must be a number between 1 and 65535.\n' >&2
  exit 1
fi

if [[ -n "$auth_username" || -n "$auth_password" ]]; then
  if [[ -z "$auth_username" || -z "$auth_password" ]]; then
    printf 'DSH_AUTH_USERNAME and DSH_AUTH_PASSWORD must be set together (or both left empty to disable auth).\n' >&2
    exit 1
  fi
  if [[ ! "$auth_username" =~ ^[A-Za-z0-9._-]+$ ]]; then
    printf 'DSH_AUTH_USERNAME must contain only letters, numbers, dot, underscore, or hyphen.\n' >&2
    exit 1
  fi
fi

install -d -m 0700 -o node -g node /data/dsh /data/dsh/home
install -d -m 0750 -o node -g node /workspace
install -d -m 0700 -o caddy -g caddy /data/caddy /data/caddy/config


install -d -m 0750 -o root -g caddy /run/dsh-auth
auth_file=/run/dsh-auth/auth.caddy
if [[ -n "$auth_username" ]]; then
  password_hash="$(caddy hash-password --algorithm argon2id --plaintext "$auth_password")"
  printf 'basic_auth argon2id {\n\t%s %s\n}\n' "$auth_username" "$password_hash" >"$auth_file"
  auth_mode="basic auth enabled for user '$auth_username'"
else
  : >"$auth_file"
  auth_mode="NO AUTHENTICATION - anyone who can reach this port has full access (settings, API keys, terminal)"
fi
chown root:caddy "$auth_file"
chmod 0640 "$auth_file"
unset DSH_AUTH_USERNAME DSH_AUTH_PASSWORD auth_password password_hash

pids=()
cleanup() {
  if (( ${#pids[@]} )); then
    kill -TERM "${pids[@]}" 2>/dev/null || true
    wait "${pids[@]}" 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

DSH_AUTH_PROXY=1 DSH_TELEMETRY_DISABLED=1 /usr/local/bin/dsh \
  web --no-open --host 127.0.0.1 --port 3080 &
dsh_pid=$!
pids+=("$dsh_pid")

ready=false
for _ in {1..60}; do
  if curl -fsS --max-time 2 http://127.0.0.1:3080/ >/dev/null 2>&1; then
    ready=true
    break
  fi
  if ! kill -0 "$dsh_pid" 2>/dev/null; then
    wait "$dsh_pid"
    exit $?
  fi
  sleep 1
done

if [[ "$ready" != true ]]; then
  printf 'DeepSeek Harness did not become ready within 60 seconds.\n' >&2
  exit 1
fi

gosu caddy env \
  XDG_DATA_HOME=/data/caddy \
  XDG_CONFIG_HOME=/data/caddy/config \
  PORT="$port" \
  caddy run --config /etc/caddy/Caddyfile --adapter caddyfile &
caddy_pid=$!
pids+=("$caddy_pid")

log "DeepSeek Harness is listening on http://0.0.0.0:$port inside the container ($auth_mode)."

status=0
wait -n "$dsh_pid" "$caddy_pid" || status=$?
exit "$status"
