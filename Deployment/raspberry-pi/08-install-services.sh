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
load_env
[[ -x "$HH_PROJECT_DIR/bin/honghuang-api" ]] || die "API 二进制不存在，请先运行 07-build.sh"
[[ -x "$HH_PROJECT_DIR/bin/world_server" ]] || die "WorldServer 二进制不存在，请先运行 07-build.sh"
sudo tee /etc/systemd/system/honghuang-api.service >/dev/null <<EOF
[Unit]
Description=HongHuangWorld Go API
After=network-online.target docker.service
Wants=network-online.target
[Service]
Type=simple
User=$USER
WorkingDirectory=$HH_PROJECT_DIR
EnvironmentFile=$HH_ENV_FILE
ExecStart=$HH_PROJECT_DIR/bin/honghuang-api
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
[Install]
WantedBy=multi-user.target
EOF
sudo tee /etc/systemd/system/honghuang-world-server.service >/dev/null <<EOF
[Unit]
Description=HongHuangWorld C++ World Server
After=network-online.target docker.service honghuang-api.service
Requires=honghuang-api.service
[Service]
Type=simple
User=$USER
WorkingDirectory=$HH_PROJECT_DIR
EnvironmentFile=$HH_ENV_FILE
ExecStart=$HH_PROJECT_DIR/bin/world_server
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable honghuang-api honghuang-world-server
sudo systemctl restart honghuang-api
for n in $(seq 1 30); do
  curl -fsS http://127.0.0.1:8787/ready >/dev/null && break
  [[ $n -lt 30 ]] || die "API 未就绪；查看 sudo journalctl -u honghuang-api"
  sleep 2
done
sudo systemctl restart honghuang-world-server
log "服务安装并启动完成"
systemctl is-active honghuang-api
systemctl is-active honghuang-world-server
