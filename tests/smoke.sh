#!/usr/bin/env bash
# Smoke test: usage tests/smoke.sh <image>
set -Eeuo pipefail

image="${1:?usage: smoke.sh <image>}"
names=(dsh-smoke-open dsh-smoke-auth dsh-smoke-half)
cleanup() { docker rm -f "${names[@]}" >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup

code() { curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$@" || true; }
expect() {
  local want="$1" got="$2" what="$3"
  if [[ "$want" != "$got" ]]; then
    printf 'FAIL: %s (expected %s, got %s)\n' "$what" "$want" "$got" >&2
    docker logs dsh-smoke-open 2>&1 | tail -20 >&2 || true
    docker logs dsh-smoke-auth 2>&1 | tail -20 >&2 || true
    exit 1
  fi
  printf 'ok: %s (%s)\n' "$what" "$got"
}
wait_for() { # url expected-code
  for _ in $(seq 1 60); do
    [[ "$(code "$1")" == "$2" ]] && return 0
    sleep 2
  done
  return 0
}

docker run -d --name dsh-smoke-open -p 18080:8080 "$image" >/dev/null
docker run -d --name dsh-smoke-auth -p 18081:8080 \
  -e DSH_AUTH_USERNAME=admin -e DSH_AUTH_PASSWORD=smoke-pass "$image" >/dev/null
wait_for http://127.0.0.1:18080/ 200
wait_for http://127.0.0.1:18081/ 401

expect 200 "$(code http://127.0.0.1:18080/)" "no auth: home page"
expect 200 "$(code -X POST -H 'Content-Type: application/json' -d '{}' http://127.0.0.1:18080/api/settings/describe)" "no auth: API works without token"
expect 403 "$(code -X POST -H 'Origin: http://evil.example' http://127.0.0.1:18080/api/settings/describe)" "cross-site API write is rejected"
expect 401 "$(code http://127.0.0.1:18081/)" "auth: anonymous rejected"
expect 401 "$(code -u admin:wrong http://127.0.0.1:18081/)" "auth: wrong password rejected"
expect 200 "$(code -u admin:smoke-pass http://127.0.0.1:18081/)" "auth: correct password accepted"

docker run -d --name dsh-smoke-half -e DSH_AUTH_USERNAME=admin "$image" >/dev/null
sleep 5
expect false "$(docker inspect -f '{{.State.Running}}' dsh-smoke-half)" "username without password refuses to start"
echo "All smoke tests passed."
