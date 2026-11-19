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
[[ -x "$HH_PROJECT_DIR/bin/honghuang-identity" ]] || die "Identity 二进制不存在，请先运行 07-build.sh"
[[ -x "$HH_PROJECT_DIR/bin/honghuang-admin" ]] || die "Admin 二进制不存在，请先运行 07-build.sh"
[[ -x "$HH_PROJECT_DIR/bin/honghuang-chat" ]] || die "Chat 二进制不存在，请先运行 07-build.sh"
: "${CHAT_DATABASE_URL:?请先在 $HH_ENV_FILE 配置独立的 CHAT_DATABASE_URL}"
: "${IDENTITY_API_BASE:?请先在 $HH_ENV_FILE 配置 IDENTITY_API_BASE}"
: "${IDENTITY_SERVICE_TOKEN:?请先在 $HH_ENV_FILE 配置 IDENTITY_SERVICE_TOKEN}"
: "${IDENTITY_DATABASE_URL:?请先在 $HH_ENV_FILE 配置 IDENTITY_DATABASE_URL}"
: "${IDENTITY_INTERNAL_API_KEY:?请先在 $HH_ENV_FILE 配置 IDENTITY_INTERNAL_API_KEY}"
: "${IDENTITY_API_BASE:?请先在 $HH_ENV_FILE 配置 IDENTITY_API_BASE}"
: "${IDENTITY_SERVICE_TOKEN:?请先在 $HH_ENV_FILE 配置 IDENTITY_SERVICE_TOKEN}"
[[ -x "$HH_PROJECT_DIR/bin/world_server" ]] || die "WorldServer 二进制不存在，请先运行 07-build.sh"
[[ -x "$HH_PROJECT_DIR/build/world-server/world_server" ]] || die "WorldServer 构建产物不存在，请先运行 07-build.sh"
sudo tee /etc/systemd/system/honghuang-identity.service >/dev/null <<EOF
[Unit]
Description=HongHuangWorld Identity Service
After=network-online.target docker.service
Wants=network-online.target
[Service]
Type=simple
User=$USER
WorkingDirectory=$HH_PROJECT_DIR
EnvironmentFile=$HH_ENV_FILE
ExecStart=$HH_PROJECT_DIR/bin/honghuang-identity
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
[Install]
WantedBy=multi-user.target
EOF
sudo tee /etc/systemd/system/honghuang-chat.service >/dev/null <<EOF
[Unit]
Description=HongHuangWorld Chat Service
After=network-online.target docker.service honghuang-identity.service
Wants=network-online.target honghuang-identity.service
[Service]
Type=simple
User=$USER
WorkingDirectory=$HH_PROJECT_DIR
EnvironmentFile=$HH_ENV_FILE
ExecStart=$HH_PROJECT_DIR/bin/honghuang-chat
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
[Install]
WantedBy=multi-user.target
EOF
sudo tee /etc/systemd/system/honghuang-admin.service >/dev/null <<EOF
[Unit]
Description=HongHuangWorld Admin Service
After=network-online.target docker.service
Wants=network-online.target
[Service]
Type=simple
User=$USER
WorkingDirectory=$HH_PROJECT_DIR
EnvironmentFile=$HH_ENV_FILE
ExecStart=$HH_PROJECT_DIR/bin/honghuang-admin
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
[Install]
WantedBy=multi-user.target
EOF
sudo tee /etc/systemd/system/honghuang-api.service >/dev/null <<EOF
[Unit]
Description=HongHuangWorld Go API
After=network-online.target docker.service honghuang-identity.service
Wants=network-online.target honghuang-identity.service
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
sudo tee /etc/systemd/system/honghuang-underworld-server.service >/dev/null <<EOF
[Unit]
Description=HongHuangWorld Fengdu Underworld WorldServer
After=network-online.target docker.service honghuang-api.service
Requires=honghuang-api.service
Wants=network-online.target
[Service]
Type=simple
User=$USER
WorkingDirectory=$HH_PROJECT_DIR
EnvironmentFile=$HH_ENV_FILE
Environment=HH_ENV_FILE=$HH_ENV_FILE
ExecStart=/usr/bin/bash $HH_PROJECT_DIR/Deployment/start-underworld-server.sh
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable honghuang-identity honghuang-api honghuang-admin honghuang-chat honghuang-world-server honghuang-underworld-server
sudo systemctl restart honghuang-identity
for n in $(seq 1 30); do
  curl -fsS http://127.0.0.1:8789/ready >/dev/null && break
  [[ $n -lt 30 ]] || die "Identity 未就绪；确认已执行 07-migrate-identity.sh，查看 sudo journalctl -u honghuang-identity"
  sleep 2
done
sudo systemctl restart honghuang-chat
for n in $(seq 1 30); do
  curl -fsS http://127.0.0.1:8788/ready >/dev/null && break
  [[ $n -lt 30 ]] || die "Chat 未就绪；确认 CHAT_DATABASE_URL 指向独立 Chat 数据库，并查看 sudo journalctl -u honghuang-chat"
  sleep 2
done
sudo systemctl restart honghuang-admin
for n in $(seq 1 30); do
  curl -fsS http://127.0.0.1:8790/ready >/dev/null && break
  [[ $n -lt 30 ]] || die "Admin 未就绪；确认已执行 06-migrate.sh（包含 000041_admin_console_foundation），查看 sudo journalctl -u honghuang-admin"
  sleep 2
done
sudo systemctl restart honghuang-api
for n in $(seq 1 30); do
  curl -fsS http://127.0.0.1:8787/ready >/dev/null && break
  [[ $n -lt 30 ]] || die "API 未就绪；查看 sudo journalctl -u honghuang-api"
  sleep 2
done
sudo systemctl restart honghuang-world-server
sudo systemctl restart honghuang-underworld-server
log "Identity、API、Admin、Chat、青云人界 WorldServer 与冥界 WorldServer 服务安装并启动完成"
systemctl is-active honghuang-identity
systemctl is-active honghuang-api
systemctl is-active honghuang-admin
systemctl is-active honghuang-chat
systemctl is-active honghuang-world-server
systemctl is-active honghuang-underworld-server
