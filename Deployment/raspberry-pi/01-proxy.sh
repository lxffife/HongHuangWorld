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
if [[ -z "$HH_PROXY_URL" ]]; then
  log "代理已禁用（HH_PROXY_URL 为空）"
  exit 0
fi
log "配置代理：$HH_PROXY_URL"
sudo install -d -m 755 /etc/apt/apt.conf.d
sudo tee /etc/apt/apt.conf.d/99honghuang-proxy >/dev/null <<EOF
Acquire::http::Proxy "$HH_PROXY_URL";
Acquire::https::Proxy "$HH_PROXY_URL";
EOF
sudo install -d -m 755 /etc/systemd/system/docker.service.d
sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf >/dev/null <<EOF
[Service]
Environment="HTTP_PROXY=$HH_PROXY_URL"
Environment="HTTPS_PROXY=$HH_PROXY_URL"
Environment="NO_PROXY=localhost,127.0.0.1,::1"
EOF
sudo systemctl daemon-reload
if systemctl is-active --quiet docker; then sudo systemctl restart docker; fi
log "APT 与 Docker 代理配置完成"
