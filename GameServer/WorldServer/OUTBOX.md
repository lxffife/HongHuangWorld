# WorldServer Durable Outbox

WorldServer persists gameplay events to a node-local SQLite database **before** attempting delivery to the center service. Character rewards and ground-drop creation use this path. Pickup settlement is also written to the outbox before the request is acknowledged. It is replayed with the same event ID after restart; the center-service pickup endpoint must preserve event-ID idempotency.

## Configuration

- `WORLD_SERVER_OUTBOX_PATH`: database file path; default `./data/worldserver-outbox.sqlite3`.
- The parent directory is created automatically when possible.
- Keep the file and its `-wal` / `-shm` companions on persistent local storage. Do not place it on `/tmp` or an ephemeral container layer.
- Do not share one database file between multiple WorldServer processes.
- Back up the database using SQLite's online backup API, or after a clean shutdown. Copying only the main database file while WAL is active may omit committed records.

SQLite is configured with WAL journaling, `synchronous=FULL`, a 5-second busy timeout, and a bounded 10,000 pending/in-flight event capacity.

## Event delivery

Supported event types:

- `character_reward`: session ID, character ID, experience and cultivation.
- `ground_drop_create`: stable drop ID, owner/session, item, quantity, position and absolute expiry time.
- `ground_drop_pickup`: stable pickup event ID, drop ID, original drop session, requesting session, character and item snapshot.

Each event has a stable UUID/ID and exact serialized JSON payload. Re-enqueuing the same ID and identical payload is idempotent; reusing an ID with a different type or payload is rejected.

The worker claims due events from SQLite. Successful HTTP delivery marks the event `delivered`. Network errors and HTTP 5xx are persisted as retry state with exponential backoff (capped at five minutes). HTTP 4xx and malformed/unsupported events move to `dead_letter`. A process restart resets abandoned `inflight` records to `pending`; the same event ID is replayed, so the center service must keep enforcing idempotency.

The outbox retains delivered and dead-letter rows for diagnosis; they do not count against the pending/in-flight capacity. No automatic retention purge is performed yet.

## Reliability boundaries

- This protects events after their SQLite transaction commits, including process crashes and host restarts when the data directory survives.
- It does not protect against disk/device loss without backups.
- A failure to write the event (disk full, permissions, database error, or capacity reached) is logged; it cannot be described as durable acceptance.
- A pickup event is durable once enqueued, but replay still carries the requesting session ID captured at pickup time. If that session is no longer accepted by the center service after a restart/logout, the event can enter dead-letter and needs an operator/reconciliation path.
- Normal shutdown stops the outbox worker after its current delivery attempt. Pending and delayed-retry records remain on disk for the next start. A pending pickup tied to a session that the backend has since closed can be rejected on replay; the current session-recovery policy is still a boundary to address.


## Soul reward events

The worker also delivers `soul_reward` events to the center service endpoint `POST /api/v1/servers/souls/rewards`. Payload fields are `session_id`, `character_id`, `experience`, and `source`; the outbox event UUID is the reward idempotency key. Fengdu monster defeats enqueue this event with 5 soul experience and source `underworld_trial:monster_hunt`. The center service validates the node and hosted session, then atomically updates permanent soul experience and the first Fengdu trial progress. The twentieth defeat completes the trial and grants its one-time 100 soul-experience bonus.


## Bounty objective discovery contract

The center service exposes an authenticated objective-discovery endpoint for the WorldServer that currently hosts a character:

`GET /api/v1/servers/bounties/objectives?session_id=<uuid>&character_id=<uuid>`

Required headers:

- `X-World-Server-Key`: the configured shared server API key.
- `X-World-Server-Node`: this node's registered `node_key`.

The response contains only accepted objectives for that active character's current world and non-expired `in_progress` / `full` tasks. It does not expose other participants' progress. The lookup validates the live session, current character, world instance, and normal node state in one read-only database transaction.

For monster objectives, `objective_key` identifies the stable monster catalogue ID (for example, `wandering_wraith`), never the runtime spawn instance ID. On authenticated world entry, WorldServer fetches the character's accepted objective subscriptions. Only `monster_killed` subscriptions are currently cached.

When authoritative combat resolves a monster death, WorldServer matches the monster definition ID and enqueues one event per matching task into the existing SQLite outbox. The event is generated only by server-side death resolution, carries the authenticated session/character and configured task/objective IDs, and uses its own UUID as the outbox and center-service idempotency key. The outbox worker posts it to `POST /api/v1/servers/bounties/events` with the shared key and node identity. Network/5xx failures retry through the existing durable retry policy; permanent 4xx responses enter dead-letter for operator inspection.

The following lethal paths are connected: direct melee, arrow/spell projectile impact, and periodic burn damage. A single death transition is handled once because the monster is marked dead before another damage tick can be resolved. Existing character reward, soul reward/absorption, and drop events remain separate.

**Current boundaries:** subscriptions are loaded at login only; a bounty accepted while the character remains online is picked up after reconnect (periodic refresh is a follow-up). Only monster-kill objectives are delivered; exploration, escort, and item objectives are not connected yet. If local SQLite enqueue fails (disk/capacity/permission), the kill still resolves and an error is logged; no durable acceptance is claimed.
