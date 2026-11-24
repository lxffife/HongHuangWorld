#!/bin/sh
# Re-launch with Bash when invoked as: sh script.sh
if [ -z "${BASH_VERSION:-}" ]; then
  if command -v bash >/dev/null 2>&1; then exec bash "$0" "$@"; fi
  echo "[ERROR] 本脚本需要 Bash，请先安装 bash。" >&2
  exit 1
fi
set -Eeuo pipefail
source "$(dirname "$0")/lib/common.sh"

need_cmd openssl
REQUESTED_LAN_BIND_IP="${HH_LAN_BIND_IP:-}"
if [[ -f "$HH_ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$HH_ENV_FILE"
  set +a
fi
LAN_BIND_IP="${REQUESTED_LAN_BIND_IP:-${HH_LAN_BIND_IP:-$(detect_lan_ipv4)}}"
[[ -n "$LAN_BIND_IP" ]] || die "无法识别树莓派局域网 IPv4，请设置 HH_LAN_BIND_IP"
is_local_ipv4 "$LAN_BIND_IP" || die "HH_LAN_BIND_IP=$LAN_BIND_IP 不是本机已配置的局域网 IPv4 地址"
NATS_AUTH_TOKEN=""

if [[ -f "$HH_ENV_FILE" ]]; then
  # Keep every existing database password and application secret unchanged.
  set -a
  # shellcheck disable=SC1090
  source "$HH_ENV_FILE"
  set +a

  : "${CHAT_DB_NAME:=honghuang_chat}"
  : "${CHAT_DB_USER:=chat_user}"
  : "${CHAT_DB_PASSWORD:?现有环境文件缺少 CHAT_DB_PASSWORD；为避免更改数据库配置，已停止}"
  : "${NATS_PORT:=4222}"
  NATS_AUTH_TOKEN="${NATS_AUTH_TOKEN:-$(openssl rand -hex 32)}"
  [[ "$NATS_AUTH_TOKEN" =~ ^[A-Za-z0-9_-]{32,}$ ]] || die "NATS_AUTH_TOKEN 必须是至少 32 位字母、数字、下划线或连字符"
  CHAT_DATABASE_URL="postgres://$CHAT_DB_USER:$CHAT_DB_PASSWORD@127.0.0.1:5432/$CHAT_DB_NAME?sslmode=disable"
  INTERNAL_NATS_URL="nats://$NATS_AUTH_TOKEN@127.0.0.1:$NATS_PORT"
  LAN_NATS_URL="nats://$NATS_AUTH_TOKEN@$LAN_BIND_IP:$NATS_PORT"

  tmp_env="$(mktemp)"
  awk -F= '$1 !~ /^(CHAT_DATABASE_URL|CHAT_TARGET_DATABASE_URL|CHAT_PROJECTION_DATABASE_URL|CHAT_USE_PROJECTION_DATABASE|HH_LAN_BIND_IP|NATS_AUTH_TOKEN|NATS_URL|GAME_NATS_URL|CHAT_NATS_URL|NATS_LAN_URL)$/' "$HH_ENV_FILE" > "$tmp_env"
  cat >> "$tmp_env" <<EOF
CHAT_DATABASE_URL=$CHAT_DATABASE_URL
HH_LAN_BIND_IP=$LAN_BIND_IP
NATS_AUTH_TOKEN=$NATS_AUTH_TOKEN
NATS_URL=$INTERNAL_NATS_URL
GAME_NATS_URL=$INTERNAL_NATS_URL
CHAT_NATS_URL=$INTERNAL_NATS_URL
NATS_LAN_URL=$LAN_NATS_URL
EOF
  sudo install -m 600 -o "$USER" -g "$USER" "$tmp_env" "$HH_ENV_FILE"
  rm -f "$tmp_env"
  log "已安全更新局域网绑定与 NATS 认证配置；现有数据库密码、Redis 密码及业务密钥均保持不变"
  log "数据服务绑定地址：$LAN_BIND_IP；NATS 客户端 URL 已写入 $HH_ENV_FILE（不在日志中显示 token）"
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
NATS_AUTH_TOKEN="$(openssl rand -hex 32)"
HOST="${HH_ADVERTISE_HOST:-$LAN_BIND_IP}"
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
CHAT_DATABASE_URL=postgres://$CHAT_DB_USER:$CHAT_DB_PASS@127.0.0.1:5432/$CHAT_DB_NAME?sslmode=disable
REDIS_PASSWORD=$REDISPASS
REDIS_PORT=6379
HH_LAN_BIND_IP=$LAN_BIND_IP
NATS_PORT=4222
NATS_AUTH_TOKEN=$NATS_AUTH_TOKEN
NATS_MONITOR_PORT=8222
NATS_URL=nats://$NATS_AUTH_TOKEN@127.0.0.1:4222
GAME_NATS_URL=nats://$NATS_AUTH_TOKEN@127.0.0.1:4222
CHAT_NATS_URL=nats://$NATS_AUTH_TOKEN@127.0.0.1:4222
NATS_LAN_URL=nats://$NATS_AUTH_TOKEN@$LAN_BIND_IP:4222
HTTP_ADDR=:8787
DATABASE_URL=postgres://honghuang:$DBPASS@127.0.0.1:5432/honghuang?sslmode=disable
REDIS_URL=redis://:$REDISPASS@127.0.0.1:6379/0
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
log "数据服务绑定地址：$LAN_BIND_IP；NATS token 已安全写入 $HH_ENV_FILE（不在日志中显示）"