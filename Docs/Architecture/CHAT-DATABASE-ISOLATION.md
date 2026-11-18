# Chat Database Isolation

## Goal

ChatServer and GameServer must fail independently:

- Game simulation and character actions never wait for ChatServer.
- Chat history, cross-world chat, and chat socket fanout continue while Game API is unavailable.
- Identity owns accounts and login sessions. Game owns souls, characters, world instances, and gameplay state. Chat owns messages, social/chat preferences, and read-optimized projections of the minimum Game facts required for routing.

## Database ownership

| Database | Owns | Must not own |
|---|---|---|
| Identity | accounts, credentials, login sessions, token lifecycle | characters, world state, chat history |
| Game | souls, characters, gameplay, world instances, server registry, authoritative sessions | chat history and social preferences |
| Chat | messages, preferences, friend/block/request state, Game projection tables, Chat outboxes/inboxes | authoritative accounts, characters, sessions, world instances |

The Chat projection tables contain copied identifiers and selected display/routing fields only. They have no foreign keys into Identity or Game.

## Game -> Chat event contract

Game is the source of truth. It must write domain changes and a Game outbox row in the same Game DB transaction. A separate publisher sends outbox events to NATS JetStream. Game gameplay must not synchronously call ChatServer.

Initial event types:

- `game.character.created.v1`
- `game.character.updated.v1` (name, race, level, world, status)
- `game.account.current_character_changed.v1`
- `game.world_instance.upserted.v1`
- `game.server_node.heartbeat.v1`
- `game.world_session.opened.v1`
- `game.world_session.updated.v1`
- `game.world_session.closed.v1`

Every event envelope carries `version`, `event_id` (UUID), `event_type`, `aggregate_id`, `occurred_at`, and a typed payload. Consumers must be idempotent by `event_id`. Projection handlers must reject unsupported versions and validate identifiers before applying an event.

The Chat consumer uses a durable JetStream consumer and stores each event in `game_projection_inbox` before acknowledging it. Projection application and inbox `processed_at` update occur in one Chat DB transaction. Replayed events are safe. Ordering-sensitive aggregates must include an aggregate version/sequence in the payload; Chat ignores older versions.

## Chat request authority

- Player identity is authenticated through the Identity HTTP API. Chat does not query Identity tables or share Identity DB credentials.
- Current character and world scope are resolved from `chat_accounts` + `chat_characters`.
- Nearby recipient validation uses `chat_world_sessions` and `chat_world_instances`.
- WorldServer node authorization uses the dedicated WorldServer API key; node/instance/session facts are checked against Chat projections.
- Chat message history reads only Chat-owned tables.

A short projection lag is acceptable and must be explicit. If the required projection is missing or stale, Chat rejects that chat operation safely; it does not fall back to querying Game DB.

## Chat -> Game delivery

Chat's own message outbox publishes `honghuang.chat.events.v1` through JetStream. Game/WorldServer consumes these events independently. NATS outage delays cross-process delivery but must not roll back committed chat history. Local ChatServer delivery remains available.

## Migration

1. Back up the existing Game DB and preserve the current deployment configuration.
2. Provision a physically/logically separate Chat PostgreSQL database and a least-privilege Chat role.
3. Run `bash Deployment/raspberry-pi/09-migrate-chat.sh` to provision the dedicated Chat role/database and apply `Database/chat-migrations/000001_chat_schema.up.sql`. The script deliberately leaves `CHAT_DATABASE_URL` unchanged.
4. Deploy the Game outbox publisher and Chat projection consumer before switching traffic.
5. Backfill accounts' current-character mapping, character display/routing data, server nodes, instances, and active/recent sessions into Chat projections. Backfill must be repeatable and must not overwrite newer event versions.
6. Copy the last 30 days of chat history and chat social data into Chat DB. Preserve message IDs, client IDs, timestamps, sender snapshots, and nearby recipient snapshots. Do not delete source rows during this step.
7. Switch ChatServer to the new Chat DB only after projection lag is zero and consistency checks pass.
8. Verify player send/history, WorldServer nearby/world/cross-world fanout, reconnect/replay, 30-day retention, and behavior while Game API is stopped.
9. Only after acceptance remove the old Game DB chat tables and credentials from ChatServer.


## Implemented Game transactional outbox (migration 000043)

The Game database now has a transactional `game_event_outbox`. PostgreSQL triggers append events in the same transaction as these source changes:

- Character create/update: `game.character.created.v1`, `game.character.updated.v1`
- Soul current-character change: `game.account.current_character_changed.v1`
- World instance changes: `game.world_instance.upserted.v1`
- Server registry heartbeat/status changes: `game.server_node.heartbeat.v1`
- World session lifecycle changes: `game.world_session.opened.v1`, `game.world_session.updated.v1`, `game.world_session.closed.v1`

Each event has a UUID, a globally increasing event/aggregate sequence, event type, aggregate ID, UTC occurrence time, and typed data. Trigger insertion is atomic with the source row transaction; a rollback removes both the domain change and its outbox event.

The API process runs `internal/gameevents.RunOutboxPublisher` independently. It claims rows using `FOR UPDATE SKIP LOCKED`, leases them, publishes to JetStream subject `honghuang.game.events.v1`, and marks them published only after JetStream acknowledges. Retries use the same event UUID as the NATS message ID. NATS connection or stream setup failure does not prevent the API from starting; pending events remain in PostgreSQL.

The current publisher is a single background worker per API process. If multiple API replicas are deployed, outbox leases prevent duplicate simultaneous claims, and consumers must still be idempotent because a crash after JetStream acknowledgement but before marking the row published causes a safe redelivery. The publisher orders each claimed batch by event sequence; consumers must use `aggregate_version` to ignore stale events.

JetStream currently retains the event stream for 30 days. Chat projection bootstrap/backfill remains required for a consumer that is offline beyond that window. No Chat cutover is implied by this migration.

## Current implementation status

- Chat runs as a separate process and reads `CHAT_DATABASE_URL`.
- Chat authentication can call the independent Identity service.
- Chat still contains direct SQL reads of Game tables, and the existing Game DB chat tables still have foreign keys to Game entities.
- The schema in `Database/chat-migrations` is the target standalone schema; Chat service code, event publisher/consumer, backfill, and cutover are not yet complete.
- Do not point production `CHAT_DATABASE_URL` at this schema yet. The current ChatServer SQL still expects the legacy Game DB layout.
