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

# Idempotently add LAN binding and NATS auth to an existing env file.
# Existing database/Redis/application credentials are never regenerated.
bash "$HH_SCRIPT_DIR/04-configure.sh"
load_env

: "${POSTGRES_USER:?环境文件缺少 POSTGRES_USER}"
: "${POSTGRES_DB:?环境文件缺少 POSTGRES_DB}"
: "${POSTGRES_PASSWORD:?环境文件缺少 POSTGRES_PASSWORD}"
: "${REDIS_PASSWORD:?环境文件缺少 REDIS_PASSWORD}"
: "${NATS_AUTH_TOKEN:?环境文件缺少 NATS_AUTH_TOKEN}"
: "${HH_LAN_BIND_IP:?环境文件缺少 HH_LAN_BIND_IP}"
is_local_ipv4 "$HH_LAN_BIND_IP" || die "HH_LAN_BIND_IP=$HH_LAN_BIND_IP 不是树莓派当前网卡地址；请先修正 $HH_ENV_FILE"

assert_existing_data_volume() {
  local container="$1" destination="$2" info
  if ! docker_cmd inspect "$container" >/dev/null 2>&1; then
    log "容器 $container 尚不存在，将由 Compose 首次创建"
    return
  fi

  local project_label
  project_label="$(docker_cmd inspect --format '{{ index .Config.Labels "com.docker.compose.project" }}' "$container" 2>/dev/null || true)"
  [[ -n "$project_label" && "$project_label" != "<no value>" ]] ||
    die "容器 $container 没有 Compose project 标签。为防止 Compose 创建新的空数据卷，已停止；请先检查该容器的挂载和创建方式。"

  info="$(docker_cmd inspect --format "{{range .Mounts}}{{if eq .Destination \"$destination\"}}{{.Type}}|{{.Name}}{{end}}{{end}}" "$container")"
  [[ "$info" == volume\|* ]] ||
    die "容器 $container 的 $destination 不是 Docker named volume（检测到：$info）。为防止数据丢失，已停止。"
  log "数据保护检查通过：$container -> $info"
}

# Verify the existing named volumes before Compose recreates containers to
# apply the new port bindings. No volume is removed or reinitialized.
assert_existing_data_volume honghuang-postgres /var/lib/postgresql/data
assert_existing_data_volume honghuang-redis /data
assert_existing_data_volume honghuang-nats /data

log "使用 Compose project：$(resolve_compose_project_name)"
log "将 PostgreSQL / Redis / NATS 客户端端口绑定到：$HH_LAN_BIND_IP"
log "NATS monitor 仍仅绑定 127.0.0.1；不会向 LAN 开放 8222"
compose up -d

postgres_ready=0
redis_ready=0
nats_ready=0
for n in $(seq 1 60); do
  if compose exec -T postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null 2>&1; then
    postgres_ready=1
  fi
  if compose exec -T redis redis-cli --no-auth-warning -a "$REDIS_PASSWORD" ping 2>/dev/null | grep -q PONG; then
    redis_ready=1
  fi
  if curl -fsS --max-time 2 "http://127.0.0.1:${NATS_MONITOR_PORT:-8222}/healthz" >/dev/null 2>&1; then
    nats_ready=1
  fi
  if [[ "$postgres_ready" == 1 && "$redis_ready" == 1 && "$nats_ready" == 1 ]]; then
    break
  fi
  [[ "$n" -lt 60 ]] || die "数据库/缓存/消息服务等待 120 秒仍未全部就绪；查看 docker compose logs postgres redis nats"
  sleep 2
done

log "PostgreSQL、Redis、NATS 均已就绪"

# The NATS token and authenticated URLs are read from the shared env file by
# these services. Restart only units that are already installed.
for service in honghuang-chat honghuang-api honghuang-world-server honghuang-underworld-server; do
  if sudo systemctl cat "$service.service" >/dev/null 2>&1; then
    log "重启 NATS 客户端服务：$service"
    sudo systemctl restart "$service.service"
  fi
done

log "局域网数据服务已启动（数据卷保留）"
log "PostgreSQL：$HH_LAN_BIND_IP:${POSTGRES_PORT:-5432}"
log "Redis：$HH_LAN_BIND_IP:${REDIS_PORT:-6379}"
log "NATS：$HH_LAN_BIND_IP:${NATS_PORT:-4222}（需要 NATS_AUTH_TOKEN）"
log "NATS monitor：仅树莓派本机 127.0.0.1:${NATS_MONITOR_PORT:-8222}"