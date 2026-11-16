#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/lib/common.sh"
load_env
compose up -d
for n in $(seq 1 60); do
  compose exec -T postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null 2>&1 && { log "PostgreSQL 已就绪"; exit 0; }
  [[ $n -lt 60 ]] || die "PostgreSQL 等待 120 秒仍未就绪；运行 docker compose logs postgres 查看原因"
  sleep 2
done
