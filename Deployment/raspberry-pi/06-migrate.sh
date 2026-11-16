#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/lib/common.sh"
load_env
[[ -d "$HH_PROJECT_DIR/Database/migrations" ]] || die "找不到 Database/migrations"
compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "CREATE TABLE IF NOT EXISTS schema_migrations(version VARCHAR(16) PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now());"
count="$(compose exec -T postgres psql -At -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c 'SELECT count(*) FROM schema_migrations;')"
has="$(compose exec -T postgres psql -At -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT to_regclass('public.accounts') IS NOT NULL;")"
[[ ! ( "$count" == 0 && "$has" == t ) ]] || die "数据库已有 accounts 表但无迁移账本；为避免破坏现有数据，已停止"
shopt -s nullglob
migrations=("$HH_PROJECT_DIR"/Database/migrations/*.up.sql)
(("${#migrations[@]}" > 0)) || die "没有找到 *.up.sql 迁移文件"
for f in "${migrations[@]}"; do
  version="$(basename "$f" | cut -d_ -f1)"
  [[ "$version" =~ ^[0-9]+$ ]] || die "无法识别迁移版本：$f"
  done_already="$(compose exec -T postgres psql -At -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT EXISTS(SELECT 1 FROM schema_migrations WHERE version='$version');")"
  [[ "$done_already" == t ]] && { log "跳过已应用迁移 $version"; continue; }
  log "执行迁移 $version"
  compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "$f"
  compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "INSERT INTO schema_migrations(version) VALUES ('$version');"
done
log "数据库迁移检查完成"
