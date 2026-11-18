#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
load_env
: "${IDENTITY_DB_NAME:=honghuang_identity}"
: "${IDENTITY_DB_USER:=identity_user}"
: "${IDENTITY_DB_PASSWORD:?Set IDENTITY_DB_PASSWORD in $HH_ENV_FILE}"
: "${IDENTITY_DATABASE_URL:?Set IDENTITY_DATABASE_URL in $HH_ENV_FILE}"
MIGRATION="$HH_PROJECT_DIR/Database/identity-migrations/000001_identity_schema.up.sql"
[[ -f "$MIGRATION" ]] || die "找不到 Identity schema migration: $MIGRATION"

log "准备 Identity 数据库 $IDENTITY_DB_NAME；不会修改现有游戏数据库"
compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -v db_name="$IDENTITY_DB_NAME" -v db_user="$IDENTITY_DB_USER" -v db_password="$IDENTITY_DB_PASSWORD" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'db_user', :'db_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'db_user')\\gexec
SELECT format('ALTER ROLE %I WITH LOGIN PASSWORD %L', :'db_user', :'db_password')\\gexec
SELECT format('CREATE DATABASE %I OWNER %I', :'db_name', :'db_user')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'db_name')\\gexec
SQL

compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$IDENTITY_DB_NAME" <<'SQL'
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE TABLE IF NOT EXISTS schema_migrations (
  version VARCHAR(32) PRIMARY KEY,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
SQL
applied="$(compose exec -T postgres psql -At -U "$POSTGRES_USER" -d "$IDENTITY_DB_NAME" \
  -c "SELECT EXISTS(SELECT 1 FROM schema_migrations WHERE version='000001');")"
if [[ "$applied" == "t" ]]; then
  log "Identity migration 000001 已应用，跳过"
else
  log "执行 Identity migration 000001"
  compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$IDENTITY_DB_USER" -d "$IDENTITY_DB_NAME" < "$MIGRATION"
  compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$IDENTITY_DB_NAME" \
    -c "INSERT INTO schema_migrations(version) VALUES ('000001') ON CONFLICT DO NOTHING;"
fi
log "Identity schema 初始化完成。注意：这只创建空库结构，不会搬迁现有玩家账号。"
