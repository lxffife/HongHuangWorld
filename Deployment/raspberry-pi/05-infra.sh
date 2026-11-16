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
compose up -d
for n in $(seq 1 60); do
  compose exec -T postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null 2>&1 && { log "PostgreSQL 已就绪"; exit 0; }
  [[ $n -lt 60 ]] || die "PostgreSQL 等待 120 秒仍未就绪；运行 docker compose logs postgres 查看原因"
  sleep 2
done
