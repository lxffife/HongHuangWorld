#!/usr/bin/env bash
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

compose() {
  if docker info >/dev/null 2>&1; then
    docker compose --env-file "$HH_ENV_FILE" -f "$HH_PROJECT_DIR/Deployment/docker-compose.yml" "$@"
  else
    sudo docker compose --env-file "$HH_ENV_FILE" -f "$HH_PROJECT_DIR/Deployment/docker-compose.yml" "$@"
  fi
}
