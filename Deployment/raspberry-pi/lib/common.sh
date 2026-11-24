#!/bin/sh
# Re-launch with Bash when invoked as: sh script.sh
if [ -z "${BASH_VERSION:-}" ]; then
  if command -v bash >/dev/null 2>&1; then
    exec bash "$0" "$@"
  fi
  echo "[ERROR] 本脚本需要 Bash，请先安装 bash。" >&2
  exit 1
fi
set -Eeuo pipefail

HH_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HH_DEPLOY_DIR="$(cd -- "$HH_SCRIPT_DIR/.." && pwd)"
HH_PROJECT_DIR="${HH_PROJECT_DIR:-$(cd -- "$HH_DEPLOY_DIR/.." && pwd)}"
HH_ENV_FILE="${HH_ENV_FILE:-/etc/honghuang-world.env}"
HH_PROXY_URL="${HH_PROXY_URL-http://192.168.124.16:17891}"
HH_REPO="https://github.com/liflife/HongHuangWorld.git"
HH_BRANCH="${HH_BRANCH:-feature/p0-foundation}"
HH_GO_VERSION="1.24.0"

log() { printf '\n[%s] %s\n' "$(date '+%F %T')" "$*"; }
die() { echo "[ERROR] $*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "缺少命令：$1"; }

if [[ -n "$HH_PROXY_URL" ]]; then
  export HTTP_PROXY="$HH_PROXY_URL" HTTPS_PROXY="$HH_PROXY_URL" ALL_PROXY="$HH_PROXY_URL"
  export http_proxy="$HH_PROXY_URL" https_proxy="$HH_PROXY_URL" all_proxy="$HH_PROXY_URL"
  NO_PROXY="localhost,127.0.0.1,::1"
  export NO_PROXY no_proxy="$NO_PROXY"
fi

load_env() {
  [[ -f "$HH_ENV_FILE" ]] || die "环境文件不存在：$HH_ENV_FILE，请先运行 04-configure.sh"
  set -a
  # shellcheck disable=SC1090
  source "$HH_ENV_FILE"
  set +a
}

docker_cmd() {
  if docker info >/dev/null 2>&1; then
    docker "$@"
  else
    sudo docker "$@"
  fi
}

resolve_compose_project_name() {
  local container label discovered=""
  if [[ -n "${HH_COMPOSE_PROJECT_NAME:-}" ]]; then
    printf '%s' "$HH_COMPOSE_PROJECT_NAME"
    return
  fi
  for container in honghuang-postgres honghuang-redis honghuang-nats; do
    if docker_cmd inspect "$container" >/dev/null 2>&1; then
      label="$(docker_cmd inspect --format '{{ index .Config.Labels "com.docker.compose.project" }}' "$container" 2>/dev/null || true)"
      if [[ -n "$label" && "$label" != "<no value>" ]]; then
        if [[ -n "$discovered" && "$discovered" != "$label" ]]; then
          die "现有容器的 Compose project 标签不一致：$discovered / $label"
        fi
        discovered="$label"
      fi
    fi
  done
  printf '%s' "${discovered:-deployment}"
}

compose() {
  local project_name
  project_name="$(resolve_compose_project_name)"
  docker_cmd compose --project-name "$project_name" --env-file "$HH_ENV_FILE" -f "$HH_PROJECT_DIR/Deployment/docker-compose.yml" "$@"
}

detect_lan_ipv4() {
  local iface
  iface="$(ip -4 route show default 2>/dev/null | awk 'NR==1 {print $5}')"
  if [[ -n "$iface" ]]; then
    ip -4 -o addr show dev "$iface" scope global 2>/dev/null |
      awk 'NR==1 {split($4, a, "/"); print a[1]}'
    return
  fi
  hostname -I 2>/dev/null | tr ' ' '\n' | awk '$1 !~ /^127\./ && index($1, ":") == 0 {print; exit}'
}

is_local_ipv4() {
  local candidate="$1"
  [[ "$candidate" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  ip -4 -o addr show scope global 2>/dev/null |
    awk '{split($4, a, "/"); print a[1]}' |
    grep -Fxq "$candidate"
}