#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
load_env

: "${CHAT_DB_NAME:=honghuang_chat}"
: "${CHAT_DB_USER:=chat_user}"
: "${CHAT_DB_PASSWORD:?Set CHAT_DB_PASSWORD in $HH_ENV_FILE}"
: "${CHAT_TARGET_DATABASE_URL:?Set CHAT_TARGET_DATABASE_URL in $HH_ENV_FILE}"

MIGRATION="$HH_PROJECT_DIR/Database/chat-migrations/000001_chat_schema.up.sql"
[[ -f "$MIGRATION" ]] || die "找不到 Chat schema migration: $MIGRATION"

log "准备独立 Chat 数据库 $CHAT_DB_NAME；不会修改 CHAT_DATABASE_URL，也不会切换现有 ChatServer"
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

applied="$(compose exec -T postgres psql -At -U "$CHAT_DB_USER" -d "$CHAT_DB_NAME" \
  -c "SELECT EXISTS(SELECT 1 FROM schema_migrations WHERE version='000001');")"
if [[ "$applied" == "t" ]]; then
  log "Chat migration 000001 已应用，跳过"
else
  count="$(compose exec -T postgres psql -At -U "$CHAT_DB_USER" -d "$CHAT_DB_NAME" \
    -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_name='chat_messages';")"
  [[ "$count" == "0" ]] || die "目标 Chat 数据库已有 chat_messages 但无迁移记录；为防止覆盖数据已停止"
  log "执行独立 Chat schema migration 000001"
  compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$CHAT_DB_USER" -d "$CHAT_DB_NAME" < "$MIGRATION"
  compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$CHAT_DB_USER" -d "$CHAT_DB_NAME" \
    -c "INSERT INTO schema_migrations(version) VALUES ('000001') ON CONFLICT DO NOTHING;"
fi

log "独立 Chat 数据库结构已创建。现有 ChatServer 仍使用 CHAT_DATABASE_URL 指向的旧库；不要手动切换，等待代码迁移与数据回填完成。"
