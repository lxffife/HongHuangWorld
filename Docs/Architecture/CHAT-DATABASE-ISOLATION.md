# Chat Database Isolation

## Final architecture

Identity, Game, and Chat are three independently operated services with three physically/logically separate PostgreSQL databases.

| Database | Authoritative data | Must not own |
|---|---|---|
| Identity | player accounts, credentials, login sessions, token lifecycle | characters, world state, chat history |
| Game | souls, characters, gameplay, world instances, server registry, authoritative world sessions | chat history, friends, blocks, chat preferences |
| Chat | messages, preferences, friendships, private requests, blocks, Game read projections, Chat inbox/outbox | credentials and authoritative gameplay state |

Chat must never connect to or query the Game database. Game must never query Chat tables in gameplay request paths. Identity authentication is performed through the Identity service API.

## Runtime connections

- Game API: `DATABASE_URL` -> Game database.
- Identity service: `IDENTITY_DATABASE_URL` -> Identity database.
- Chat service: `CHAT_DATABASE_URL` -> dedicated Chat database.
- Chat's Game projection consumer uses the same Chat database connection/pool as the Chat API. It does not open a second database or connect to Game.
- Chat authentication requires `IDENTITY_API_BASE` and `IDENTITY_SERVICE_TOKEN`.
- Game -> Chat events use `GAME_NATS_URL`, falling back to `NATS_URL`.

The Chat process refuses to start if `CHAT_DATABASE_URL` is equal to `DATABASE_URL`. There is no legacy database mode, projection database switch, or runtime fallback to Game SQL.

## Game -> Chat projection

Game is the source of truth. Database triggers append domain events to `game_event_outbox` in the same Game DB transaction as the source change. The Game publisher sends those events to NATS JetStream subject `honghuang.game.events.v1` and marks them published only after JetStream acknowledges.

Events maintain these Chat-owned projections:

- `chat_accounts`: account to current-character mapping.
- `chat_characters`: character display name, race, level, world, and status.
- `chat_server_nodes`: node status and heartbeat.
- `chat_world_instances`: instance/world/node routing.
- `chat_world_sessions`: character/instance/node/session routing.

Chat's durable consumer `CHAT_GAME_PROJECTION` validates event envelopes, deduplicates by event UUID, applies projection updates and aggregate versions in one Chat DB transaction, then acknowledges JetStream. Redelivered events are safe. Chat rejects operations when required projection state is absent or stale; it never queries Game as a fallback.

JetStream retains Game events for 30 days. Projection bootstrap/rebuild procedures must be provided before operating a consumer beyond that retention window.

## Chat -> Game delivery

Chat persists a message and its fanout intent in the same Chat database transaction using `chat_event_outbox`. The Chat publisher sends events to `honghuang.chat.events.v1`. Game/WorldServer consumes those events independently. NATS outages may delay cross-service fanout but do not roll back committed chat history or block Game gameplay.

## Fresh database initialization

There is no legacy chat-data copy step because this project has not entered user testing and the standalone Chat database is the authoritative store from the beginning.

1. Provision a dedicated PostgreSQL database `honghuang_chat` and role `chat_user`.
2. Set `CHAT_DATABASE_URL` to that database. It must not equal `DATABASE_URL`.
3. Run `bash Deployment/raspberry-pi/09-migrate-chat.sh` to apply every versioned migration in `Database/chat-migrations`.
4. Start Identity, Game, NATS, and Chat services.
5. Verify that the Game projection consumer is ready and that new characters, account-current-character changes, worlds, nodes, and sessions appear in Chat projection tables.
6. Verify player chat send/history and WorldServer nearby/world/cross-world delivery.
7. Stop Game API temporarily and confirm Chat history and cross-world chat remain available. Stop Chat temporarily and confirm Game movement/combat/world operations remain available.

The old Game database's historical chat tables are not read by Chat and are not copied. They may be removed later with a deliberate Game migration after the independent Chat service is accepted.

## Retention and operations

- Chat message history is retained for 30 days.
- Chat cleanup runs in the Chat process against Chat's own database.
- Game outbox cleanup removes only acknowledged events older than seven days in bounded batches; unpublished events are retained.
- Projection consumer and API share Chat's connection pool. A projection consumer failure must be visible in logs/metrics, but does not make Game depend on Chat.
- Never point `CHAT_DATABASE_URL` at the Game or Identity database.
