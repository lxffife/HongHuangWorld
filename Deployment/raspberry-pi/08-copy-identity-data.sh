#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
load_env
: "${IDENTITY_DB_NAME:=honghuang_identity}"
: "${IDENTITY_DB_USER:=identity_user}"
: "${IDENTITY_DB_PASSWORD:?Set IDENTITY_DB_PASSWORD in $HH_ENV_FILE}"
: "${IDENTITY_DATABASE_URL:?Set IDENTITY_DATABASE_URL in $HH_ENV_FILE}"
if [[ "${CONFIRM_IDENTITY_DATA_COPY:-}" != "YES" ]]; then
  die "这是账号数据复制操作。先完成数据库备份，并使用 CONFIRM_IDENTITY_DATA_COPY=YES 显式确认。"
fi

source_accounts="$(compose exec -T postgres psql -At -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c 'SELECT count(*) FROM public.accounts')"
source_sessions="$(compose exec -T postgres psql -At -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c 'SELECT count(*) FROM public.account_sessions')"
target_accounts="$(compose exec -T postgres psql -At -U "$IDENTITY_DB_USER" -d "$IDENTITY_DB_NAME" -c 'SELECT count(*) FROM public.accounts')"
target_sessions="$(compose exec -T postgres psql -At -U "$IDENTITY_DB_USER" -d "$IDENTITY_DB_NAME" -c 'SELECT count(*) FROM public.account_sessions')"

if [[ "$target_accounts" != "0" || "$target_sessions" != "0" ]]; then
  die "Identity 目标表非空（accounts=$target_accounts, sessions=$target_sessions），拒绝覆盖；请先人工核对目标数据。"
fi

log "准备复制 accounts=$source_accounts、account_sessions=$source_sessions"
log "密码哈希、账号 UUID、会话 Token 哈希与过期/撤销时间均原样复制；不会导出明文密码或 Token。"

# pg_dump emits SQL INSERT statements. Wrap the complete stream in one transaction:
# any duplicate/constraint/import error rolls back the entire copy.
set -o pipefail
{
  printf 'BEGIN;\n'
  compose exec -T postgres pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
    --data-only --inserts --no-owner --no-privileges \
    --table=public.accounts --table=public.account_sessions
  printf '\nCOMMIT;\n'
} | compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$IDENTITY_DB_USER" -d "$IDENTITY_DB_NAME"

copied_accounts="$(compose exec -T postgres psql -At -U "$IDENTITY_DB_USER" -d "$IDENTITY_DB_NAME" -c 'SELECT count(*) FROM public.accounts')"
copied_sessions="$(compose exec -T postgres psql -At -U "$IDENTITY_DB_USER" -d "$IDENTITY_DB_NAME" -c 'SELECT count(*) FROM public.account_sessions')"
if [[ "$copied_accounts" != "$source_accounts" || "$copied_sessions" != "$source_sessions" ]]; then
  die "复制后数量不一致：源 accounts=$source_accounts sessions=$source_sessions；目标 accounts=$copied_accounts sessions=$copied_sessions。请暂停切换并保留两边数据供排查。"
fi
log "账号数据复制完成且数量一致。旧库数据未删除；暂时不要切换登录流量，下一步需要停写窗口和身份服务验收。"
