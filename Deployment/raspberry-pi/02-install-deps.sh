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
source "$(dirname "$0")/lib/common.sh"
if [[ "${HH_FORCE_APT_UPDATE:-0}" == "1" ]] || ! find /var/lib/apt/lists -maxdepth 1 -type f -name '*InRelease' -mmin -360 -print -quit 2>/dev/null | grep -q .; then
  log "更新 APT 软件包索引"
  sudo apt-get update
else
  log "APT 索引在 6 小时内更新过，跳过 apt-get update"
fi
sudo apt-get install -y ca-certificates curl git build-essential cmake pkg-config libenet-dev libcurl4-openssl-dev nlohmann-json3-dev postgresql-client openssl
if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
  sudo apt-get install -y docker.io docker-compose-v2
fi
sudo systemctl enable --now docker
if [[ -n "$HH_PROXY_URL" ]]; then sudo systemctl restart docker; fi
if ! command -v go >/dev/null 2>&1 || [[ "$(go version | awk '{print $3}')" != "go$HH_GO_VERSION" ]]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  curl -fL --retry 3 "https://go.dev/dl/go${HH_GO_VERSION}.linux-arm64.tar.gz" -o "$tmp/go.tgz"
  sudo rm -rf /usr/local/go
  sudo tar -C /usr/local -xzf "$tmp/go.tgz"
fi
grep -q '/usr/local/go/bin' "$HOME/.profile" 2>/dev/null || echo 'export PATH=/usr/local/go/bin:$HOME/go/bin:$PATH' >> "$HOME/.profile"
log "系统依赖、Docker、Go 安装完成"
