#!/bin/sh
# Re-launch with Bash when invoked as: sh script.sh
if [ -z "${BASH_VERSION:-}" ]; then
  if command -v bash >/dev/null 2>&1; then exec bash "$0" "$@"; fi
  echo "[ERROR] 本脚本需要 Bash，请先安装 bash。" >&2
  exit 1
fi
set -Eeuo pipefail
source "$(dirname "$0")/lib/common.sh"
if [[ -f "$HH_ENV_FILE" ]]; then
  log "环境文件已存在，保留现有密码与配置：$HH_ENV_FILE"
  exit 0
fi
DBPASS="$(openssl rand -hex 24)"
IDENTITY_DB_PASS="$(openssl rand -hex 24)"
CHAT_DB_PASS="$(openssl rand -hex 24)"
IDENTITY_API_KEY="$(openssl rand -hex 32)"
CHAT_DB_NAME=honghuang_chat
CHAT_DB_USER=chat_user
REDISPASS="$(openssl rand -hex 24)"
APIKEY="$(openssl rand -hex 32)"
HOST="${HH_ADVERTISE_HOST:-$(hostname -I | awk '{print $1}')}"
[[ -n "$HOST" ]] || die "无法识别树莓派 IP，请设置 HH_ADVERTISE_HOST"
sudo install -d -m 755 "$(dirname "$HH_ENV_FILE")"
sudo tee "$HH_ENV_FILE" >/dev/null <<EOF
POSTGRES_DB=honghuang
POSTGRES_USER=honghuang
POSTGRES_PASSWORD=$DBPASS
POSTGRES_PORT=5432
IDENTITY_DB_NAME=honghuang_identity
IDENTITY_DB_USER=identity_user
IDENTITY_DB_PASSWORD=$IDENTITY_DB_PASS
IDENTITY_DATABASE_URL=postgres://identity_user:$IDENTITY_DB_PASS@127.0.0.1:5432/honghuang_identity?sslmode=disable
IDENTITY_HTTP_ADDR=127.0.0.1:8789
IDENTITY_INTERNAL_API_KEY=$IDENTITY_API_KEY
IDENTITY_API_BASE=http://127.0.0.1:8789
IDENTITY_SERVICE_TOKEN=$IDENTITY_API_KEY
CHAT_DB_NAME=$CHAT_DB_NAME
CHAT_DB_USER=$CHAT_DB_USER
CHAT_DB_PASSWORD=$CHAT_DB_PASS
CHAT_TARGET_DATABASE_URL=postgres://$CHAT_DB_USER:$CHAT_DB_PASS@127.0.0.1:5432/$CHAT_DB_NAME?sslmode=disable
CHAT_PROJECTION_DATABASE_URL=postgres://$CHAT_DB_USER:$CHAT_DB_PASS@127.0.0.1:5432/$CHAT_DB_NAME?sslmode=disable
REDIS_PASSWORD=$REDISPASS
REDIS_PORT=6379
NATS_PORT=4222
NATS_MONITOR_PORT=8222
HTTP_ADDR=:8787
DATABASE_URL=postgres://honghuang:$DBPASS@127.0.0.1:5432/honghuang?sslmode=disable
REDIS_URL=redis://:$REDISPASS@127.0.0.1:6379/0
NATS_URL=nats://127.0.0.1:4222
WORLD_SERVER_API_KEY=$APIKEY
BACKEND_URL=http://127.0.0.1:8787
WORLD_SERVER_NODE_KEY=honghuang-pi-node-01
WORLD_SERVER_BIND=0.0.0.0
WORLD_SERVER_ADVERTISE_HOST=$HOST
WORLD_SERVER_UDP_PORT=7777
WORLD_SERVER_REGION=home
WORLD_ID=qingyun_human
WORLD_SERVER_INSTANCE_KEY=qingyun-pi-qingyun-01
WORLD_SERVER_CAPACITY=30
EOF
sudo chown "$USER:$USER" "$HH_ENV_FILE"
sudo chmod 600 "$HH_ENV_FILE"
log "环境配置已生成：$HH_ENV_FILE（权限 600）"
