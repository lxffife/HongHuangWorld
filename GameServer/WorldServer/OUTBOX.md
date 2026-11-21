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

For monster objectives, `objective_key` identifies the stable monster catalogue ID (for example, `wandering_wraith`), never the runtime spawn instance ID. On authenticated world entry, WorldServer fetches the character's accepted objective subscriptions. Only `monster_killed` subscriptions are currently cached. While online, the main loop snapshots active session/character IDs every 15 seconds into a bounded refresh queue (maximum 512 queued jobs). A dedicated worker performs HTTP lookups and never reads or writes the live `players` map. Results are applied by the main loop only when both session ID and character ID still match a connected player. A failed refresh keeps the last known subscriptions and is retried on a later interval; a successful empty response clears them. Disconnects and character/session replacement therefore cannot apply stale results to a different player. The worker is stopped before player sessions are closed during shutdown.

WorldServer also maintains a bounded, server-authoritative damage ledger per monster spawn. Effective damage from melee attacks, player-owned projectiles (including arrows and spells), and periodic burn ticks is accumulated by authenticated session and character. Each spawn is limited to 256 tracked contributors. When full, a new contributor is admitted only if that contributor's current effective hit exceeds the weakest tracked contributor's accumulated damage; the weakest entry is then evicted. The center service accepts the same maximum of 256 contributors per snapshot. This avoids permanently reserving all slots for the first 256 attackers and keeps admission deterministic, but it is not a complete all-player ranking: an evicted contributor's earlier accumulated damage is no longer present in the death snapshot, and a newcomer is judged only by the current hit because their future total is not yet known. Exact attribution for an arbitrary number of attackers requires a separately designed durable/aggregated ledger rather than an in-memory 256-entry cap. On death, the server emits a damage-ranked contribution snapshot to its diagnostic log. The ledger is cleared when that spawn respawns. This is an instrumentation/foundation step only: contribution snapshots are not yet persisted or submitted to the center service, and bounty progress/rewards still use the existing last-hit attribution.

When authoritative combat resolves a monster death, WorldServer matches the monster definition ID and enqueues one event per matching task into the existing SQLite outbox. The event is generated only by server-side death resolution, carries the authenticated session/character and configured task/objective IDs, and uses its own UUID as the outbox and center-service idempotency key. The outbox worker posts it to `POST /api/v1/servers/bounties/events` with the shared key and node identity. Network/5xx failures retry through the existing durable retry policy; permanent 4xx responses enter dead-letter for operator inspection.

The following lethal paths are connected: direct melee, arrow/spell projectile impact, and periodic burn damage. A single death transition is handled once because the monster is marked dead before another damage tick can be resolved. Existing character reward, soul reward/absorption, and drop events remain separate.

**Current boundaries:** subscriptions are loaded at login only; a bounty accepted while the character remains online is picked up after reconnect (periodic refresh is a follow-up). Only monster-kill objectives are delivered; exploration, escort, and item objectives are not connected yet. If local SQLite enqueue fails (disk/capacity/permission), the kill still resolves and an error is logged; no durable acceptance is claimed.


## Bounty monster contribution ledger (migration 000059)

The center service accepts immutable death-time contribution snapshots at:

`POST /api/v1/servers/bounties/contributions`

The request uses the same `X-World-Server-Key` and `X-World-Server-Node` authentication as bounty objective events. It contains a stable event UUID, task ID, runtime monster instance ID, monster definition ID, and 1–256 contributors (session ID, character ID, effective damage, hit count).

The center service verifies the task is active and unexpired, the configured objective is a matching `monster_killed` objective, each historical session belongs to the reporting node and task world, and stores only contributors whose derived account is an accepted participant; unrelated attackers are ignored. Historical `active`, `saving`, and `closed` sessions are eligible; a contributor does not have to remain online when the outbox event is delivered. Account IDs are resolved from server-owned character/soul records and are never accepted from the payload.

Event UUID reuse with a different normalized payload is rejected. The event envelope and contributor rows are stored in the same PostgreSQL transaction and protected by immutable-record triggers.

**Important boundary:** this endpoint is an audit/persistence foundation only. It does not advance objective progress, award bounty credit, or change escrow settlement. The existing kill event still attributes objective progress to the last hitter, and settlement remains equal-share until the cooperative-counting and contribution-weighting rules are explicitly decided. WorldServer now writes these snapshots to its durable SQLite outbox and retries delivery.


## Bounty contribution snapshot delivery

On each authoritative monster death, WorldServer now creates a separate `bounty_monster_contributions` event for every matching cached monster-kill objective. The payload contains the stable task/objective identifiers, runtime monster instance ID, and the bounded damage-ranked contributor snapshot. It is persisted in the same node-local SQLite outbox and retried with the same event UUID until the center service accepts it or returns a permanent 4xx.

The outbox worker posts the snapshot to `POST /api/v1/servers/bounties/contributions`. The center service verifies each historical session against the reporting node and world, then stores only contributors who are accepted participants in that bounty. Other attackers are ignored rather than invalidating valid participant contributions.

The kill-progress event and contribution-snapshot event are now inserted together through a single SQLite transaction. If capacity, validation, or storage fails, neither event is accepted into the outbox, and the resolved combat result is not rolled back. The outbox test suite now covers whole-batch retry idempotency, payload conflicts, and all-or-nothing capacity failure.


## Atomic bounty kill outbox batches

The kill-progress event and its damage-contribution snapshot are now assembled as one batch and inserted by `DurableOutbox::enqueue_batch` under one SQLite `BEGIN IMMEDIATE` transaction. The batch validates every event ID and payload before inserting any row, treats an exact whole-batch retry as idempotent, rejects event-ID payload conflicts, and checks total capacity before insertion. A capacity or storage failure rolls back the entire batch, so the kill-progress event cannot be durably queued without its matching contribution snapshot (or vice versa).

The C++ outbox tests cover exact batch retries, conflicting retries, and capacity failure with zero partial rows.

## Player contribution history API

Participants can inspect the most recent 200 monster contribution snapshots for a bounty through:

`GET /api/v1/bounties/{taskID}/contributions`

The endpoint verifies that the authenticated account participated in the task. It returns monster instance/definition, timestamp, character ID, effective damage, and hit count. Internal session IDs and account IDs are not exposed. This is a read-only audit view; it does not change objective progress or settlement.

### Offline burn-death contribution durability

When a monster dies from a delayed burn tick after the burn owner has disconnected, WorldServer still queues the contribution snapshots represented by the monster's recorded contributor subscriptions. The killer pointer is optional: without an online authenticated killer, no kill-progress event is fabricated, but valid prior contribution evidence is preserved. Normal direct and projectile kills continue to pass their authenticated online killer and retain the existing killer-subscription gate.

### Contributor-owned bounty objective attribution

A monster damage contribution now carries the matching `monster_killed` objective subscriptions observed on that authenticated character when effective damage is applied. At death, WorldServer unions and deduplicates those task/objective subscriptions across the damage ledger. This means a non-participant final hitter no longer suppresses a contribution snapshot for a task joined by another contributor. The kill-progress event is still emitted only when the final hitter has the matching subscription; contribution snapshots are emitted for each task represented by a contributor. The center service remains authoritative and filters contributors to accepted participants.

Duplicate contribution-event IDs are also bound to the original reporting node: an exact retry from another node is rejected as an idempotency conflict, even if its JSON payload is identical.

### Publisher faction contribution audit API

- `GET /api/v1/factions/{factionID}/bounties/{taskID}/contributions`
- Requires a player bearer token and an active membership in the task's actual publishing faction.
- Only `leader` and `officer` roles may read task-wide audit data. A task published by another faction, an inactive faction, a member without an officer role, or a non-faction publisher is denied.
- Authorization locks the task, faction, and membership rows in one read transaction before reading the ledger, preventing membership revocation from racing the audit request.
- Response aggregates each character's total damage, hit count, distinct monster count, and percentage of accepted-participant damage. Snapshot events use stable keyset pagination: `limit` defaults to 50 and is capped at 100; pass the returned opaque `next_cursor` as `cursor` to fetch the next page. Aggregates always cover the full task history, independent of the event page.
- The response does not expose account IDs or world session IDs. It is read-only and does not change objective progress, participant eligibility, or settlement.


## SQLite monster contribution ledger groundwork

The local outbox database now also creates `monster_damage_contributions`, keyed by runtime monster instance, authenticated session, and character. `DurableOutbox::record_monster_contribution` atomically upserts effective damage and hit counts with signed-64-bit saturation, preserves first/last-hit timestamps, and stores the caller's complete deduplicated objective-subscription JSON. Every write requires a stable `write_id`: an exact retry is a no-op, while reusing the ID with different data is rejected. The write-ID journal is removed together with the monster ledger during finalization. A finalization tombstone rejects late writes and prevents the same runtime monster from being finalized with a different event batch. `load_monster_contributions` returns a stable damage-ranked view.

`finalize_monster_contributions` inserts all death-time outbox events and deletes that monster's live ledger rows inside one `BEGIN IMMEDIATE` transaction. If validation, event-ID conflict, or outbox capacity fails, the transaction rolls back and the contribution rows remain available for retry. Repeating an identical finalization is idempotent because existing matching outbox rows are accepted.

**Integration boundary:** these SQLite APIs are groundwork and are not yet called from the combat loop. The live gameplay path still uses its existing 256-entry in-memory map until an asynchronous persistence queue and bounded backpressure policy are integrated. Do not call the SQLite write method directly for every hit on the main game loop: WAL with `synchronous=FULL` can block combat processing. This ledger also does not restore active monsters after process restart; monster runtime state and health are not persisted. A later integration step must define stale-row expiry for runtime IDs whose monsters were not restored.
