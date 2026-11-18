#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
load_env

: "${CHAT_DB_NAME:=honghuang_chat}"
: "${CHAT_DB_USER:=chat_user}"

if [[ "${CONFIRM_CHAT_DATA_COPY:-}" != "YES" ]]; then
  die "这是聊天数据复制操作。完成 Game/Chat 数据库备份后，使用 CONFIRM_CHAT_DATA_COPY=YES 显式确认。"
fi
if [[ "${CHAT_PROJECTION_CONSUMER_PAUSED:-}" != "YES" ]]; then
  die "复制期间必须暂停 ChatServer 的 Game 投影消费者。确认暂停后设置 CHAT_PROJECTION_CONSUMER_PAUSED=YES。"
fi

target_check="$(compose exec -T postgres psql -XAt -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$CHAT_DB_NAME" -c "
SELECT
  (SELECT count(*) FROM chat_accounts) +
  (SELECT count(*) FROM chat_characters) +
  (SELECT count(*) FROM chat_server_nodes) +
  (SELECT count(*) FROM chat_world_instances) +
  (SELECT count(*) FROM chat_world_sessions) +
  (SELECT count(*) FROM chat_messages) +
  (SELECT count(*) FROM chat_preferences) +
  (SELECT count(*) FROM chat_friendships) +
  (SELECT count(*) FROM chat_private_requests) +
  (SELECT count(*) FROM chat_blocks) +
  (SELECT count(*) FROM chat_event_outbox) +
  (SELECT count(*) FROM game_projection_inbox) +
  (SELECT count(*) FROM game_projection_versions);
")"
[[ "$target_check" == "0" ]] || die "Chat 目标库并非空库（投影、消息、社交关系或事件表已有数据），拒绝覆盖。"

source_ready="$(compose exec -T postgres psql -XAt -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
SELECT to_regclass('public.chat_messages') IS NOT NULL
   AND to_regclass('public.chat_event_outbox') IS NOT NULL
   AND to_regclass('public.game_event_outbox') IS NOT NULL
   AND to_regclass('public.game_event_outbox_sequence') IS NOT NULL;
")"
[[ "$source_ready" == "t" ]] || die "Game 数据库缺少聊天表或 000043 Game 事件 Outbox。请先完成数据库迁移。"

log "开始在 REPEATABLE READ 快照中复制 Chat 投影、聊天记录和社交数据。"
log "历史消息的 sender_name/race/level 使用当前 characters 快照补齐；旧数据结构无法还原历史时刻的角色名称。"

set -o pipefail
{
  printf 'BEGIN;\n'
  compose exec -T postgres psql -XqAt -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<'SQL'
BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;

SELECT format(
  'INSERT INTO chat_accounts(account_id,current_character_id,updated_at) VALUES (%L::uuid,%L::uuid,%L::timestamptz);',
  account_id,current_character_id,updated_at
) FROM souls;

SELECT format(
  'INSERT INTO chat_characters(character_id,name,race_id,level,world_id,status,updated_at) VALUES (%L::uuid,%L,%L,%s,%L,%L,%L::timestamptz);',
  c.id,c.name,COALESCE(c.race_id,''),c.level,c.world_id,c.status,c.updated_at
) FROM characters c JOIN souls s ON s.id=c.soul_id;

SELECT format(
  'INSERT INTO chat_server_nodes(node_key,status,last_heartbeat_at,updated_at) VALUES (%L,%L,%L::timestamptz,%L::timestamptz);',
  node_key,status,last_heartbeat_at,updated_at
) FROM server_registry;

SELECT format(
  'INSERT INTO chat_world_instances(instance_id,world_id,node_key,status,updated_at) VALUES (%L::uuid,%L,%L,%L,%L::timestamptz);',
  wi.id,wi.world_id,COALESCE(sr.node_key,''),wi.status,wi.updated_at
) FROM world_instances wi LEFT JOIN server_registry sr ON sr.id=wi.server_id;

SELECT format(
  'INSERT INTO chat_world_sessions(session_id,character_id,instance_id,node_key,session_state,disconnected_at,updated_at) VALUES (%L::uuid,%L::uuid,%L::uuid,%L,%L,%L::timestamptz,%L::timestamptz);',
  ws.id,ws.character_id,ws.instance_id,COALESCE(sr.node_key,''),ws.session_state,ws.disconnected_at,ws.updated_at
) FROM world_sessions ws JOIN server_registry sr ON sr.id=ws.server_id;

SELECT format(
  'INSERT INTO chat_messages(id,channel_type,world_id,world_instance_id,nearby_recipient_character_ids,sender_character_id,recipient_character_id,client_message_id,sender_name,sender_race,sender_level,content,created_at) VALUES (%L::uuid,%L,%L,%L::uuid,%L::jsonb,%L::uuid,%L::uuid,%L::uuid,%L,%L,%s,%L,%L::timestamptz);',
  m.id,m.channel_type,m.world_id,m.world_instance_id,
  COALESCE(m.nearby_recipient_character_ids,'[]'::jsonb)::text,
  m.sender_character_id,m.recipient_character_id,m.client_message_id,
  c.name,COALESCE(c.race_id,''),c.level,m.content,m.created_at
) FROM chat_messages m JOIN characters c ON c.id=m.sender_character_id;

SELECT format(
  'INSERT INTO chat_preferences(character_id,allow_stranger_requests,allow_nearby_messages,allow_world_messages,updated_at) VALUES (%L::uuid,%L,%L,%L,%L::timestamptz);',
  character_id,allow_stranger_requests,allow_nearby_messages,allow_world_messages,updated_at
) FROM chat_preferences;

SELECT format(
  'INSERT INTO chat_friendships(id,requester_character_id,addressee_character_id,created_at) VALUES (%L::uuid,%L::uuid,%L::uuid,%L::timestamptz);',
  id,requester_character_id,addressee_character_id,created_at
) FROM chat_friendships;

SELECT format(
  'INSERT INTO chat_private_requests(id,requester_character_id,addressee_character_id,status,message,created_at,responded_at) VALUES (%L::uuid,%L::uuid,%L::uuid,%L,%L,%L::timestamptz,%L::timestamptz);',
  id,requester_character_id,addressee_character_id,status,message,created_at,responded_at
) FROM chat_private_requests;

SELECT format(
  'INSERT INTO chat_blocks(blocker_character_id,blocked_character_id,created_at) VALUES (%L::uuid,%L::uuid,%L::timestamptz);',
  blocker_character_id,blocked_character_id,created_at
) FROM chat_blocks;

-- Only unpublished fanout intents are copied. Published history is not rebroadcast.
SELECT format(
  'INSERT INTO chat_event_outbox(message_id,payload,created_at,attempts,next_attempt_at,locked_until,locked_by,last_error) VALUES (%L::uuid,%L::jsonb,%L::timestamptz,%s,now(),NULL,NULL,%L);',
  message_id,payload::text,created_at,attempts,last_error
) FROM chat_event_outbox WHERE published_at IS NULL;

-- Seed every current aggregate at the source sequence high-water mark. This
-- prevents retained older JetStream events from overwriting the copied snapshot.
SELECT format($copy$
INSERT INTO game_projection_versions(aggregate_id,aggregate_version)
SELECT aggregate_id,%s::bigint
FROM (
  SELECT character_id::text AS aggregate_id FROM chat_characters
  UNION SELECT account_id::text FROM chat_accounts
  UNION SELECT instance_id::text FROM chat_world_instances
  UNION SELECT node_key FROM chat_server_nodes
  UNION SELECT session_id::text FROM chat_world_sessions
) current_aggregates
ON CONFLICT(aggregate_id) DO UPDATE
SET aggregate_version=EXCLUDED.aggregate_version,updated_at=now();
$copy$, CASE WHEN is_called THEN last_value ELSE 0 END)
FROM game_event_outbox_sequence;

COMMIT;
SQL
  printf 'COMMIT;\n'
} | compose exec -T postgres psql -X -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$CHAT_DB_NAME"

tables=(chat_accounts chat_characters chat_server_nodes chat_world_instances chat_world_sessions chat_messages chat_preferences chat_friendships chat_private_requests chat_blocks)
for table in "${tables[@]}"; do
  source_count="$(compose exec -T postgres psql -XAt -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT count(*) FROM public.$table")"
  target_count="$(compose exec -T postgres psql -XAt -U "$POSTGRES_USER" -d "$CHAT_DB_NAME" -c "SELECT count(*) FROM public.$table")"
  [[ "$source_count" == "$target_count" ]] || die "$table 数量不一致：Game=$source_count Chat=$target_count。暂停切换并保留两边数据。"
done

source_pending="$(compose exec -T postgres psql -XAt -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT count(*) FROM chat_event_outbox WHERE published_at IS NULL")"
target_pending="$(compose exec -T postgres psql -XAt -U "$POSTGRES_USER" -d "$CHAT_DB_NAME" -c "SELECT count(*) FROM chat_event_outbox")"
[[ "$source_pending" == "$target_pending" ]] || die "待发布聊天事件数量不一致：Game=$source_pending Chat=$target_pending。"

log "Chat 历史数据复制完成，核心表数量核对一致。旧 Game 数据未删除。"
log "下一步先启动 Chat 投影消费者，检查投影延迟与消息路由；暂时不要设置 CHAT_USE_PROJECTION_DATABASE=true。"
