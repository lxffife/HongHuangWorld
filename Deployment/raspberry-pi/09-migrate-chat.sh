#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
load_env

: "${CHAT_DB_NAME:=honghuang_chat}"
: "${CHAT_DB_USER:=chat_user}"
: "${CHAT_DB_PASSWORD:?Set CHAT_DB_PASSWORD in $HH_ENV_FILE}"
: "${CHAT_DATABASE_URL:?Set CHAT_DATABASE_URL in $HH_ENV_FILE}"

MIGRATION_DIR="$HH_PROJECT_DIR/Database/chat-migrations"
[[ -d "$MIGRATION_DIR" ]] || die "找不到 Chat migrations: $MIGRATION_DIR"

[[ "$CHAT_DATABASE_URL" != "${DATABASE_URL:-}" ]] || die "CHAT_DATABASE_URL 不能与 Game DATABASE_URL 相同"\nlog "准备独立 Chat 数据库 $CHAT_DB_NAME；ChatServer 将直接使用 CHAT_DATABASE_URL"
compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -v db_name="$CHAT_DB_NAME" -v db_user="$CHAT_DB_USER" -v db_password="$CHAT_DB_PASSWORD" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'db_user', :'db_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'db_user')\gexec
SELECT format('ALTER ROLE %I WITH LOGIN PASSWORD %L', :'db_user', :'db_password')\gexec
SELECT format('CREATE DATABASE %I OWNER %I', :'db_name', :'db_user')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'db_name')\gexec
SQL

compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$CHAT_DB_USER" -d "$CHAT_DB_NAME" <<'SQL'
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE TABLE IF NOT EXISTS schema_migrations (
  version VARCHAR(32) PRIMARY KEY,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
SQL

shopt -s nullglob
migrations=("$MIGRATION_DIR"/*.up.sql)
(("${#migrations[@]}" > 0)) || die "没有找到 Chat *.up.sql 迁移文件"
for migration in "${migrations[@]}"; do
  version="$(basename "$migration" | cut -d_ -f1)"
  [[ "$version" =~ ^[0-9]+$ ]] || die "无法识别 Chat 迁移版本：$migration"
  applied="$(compose exec -T postgres psql -At -U "$CHAT_DB_USER" -d "$CHAT_DB_NAME" \
    -c "SELECT EXISTS(SELECT 1 FROM schema_migrations WHERE version='$version');")"
  if [[ "$applied" == "t" ]]; then
    log "跳过已应用 Chat migration $version"
    continue
  fi
  if [[ "$version" == "000001" ]]; then
    table_exists="$(compose exec -T postgres psql -At -U "$CHAT_DB_USER" -d "$CHAT_DB_NAME" \
      -c "SELECT to_regclass('public.chat_messages') IS NOT NULL;")"
    [[ "$table_exists" == "f" ]] || die "目标 Chat 数据库已有 chat_messages 但无迁移记录；为防止覆盖数据已停止"
  fi
  log "执行 Chat migration $version"
  compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$CHAT_DB_USER" -d "$CHAT_DB_NAME" < "$migration"
  compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$CHAT_DB_USER" -d "$CHAT_DB_NAME" \
    -c "INSERT INTO schema_migrations(version) VALUES ('$version') ON CONFLICT DO NOTHING;"
done

log "独立 Chat 数据库结构已创建。ChatServer 直接连接 CHAT_DATABASE_URL；Game 状态通过 NATS 投影进入 Chat 数据库。"
