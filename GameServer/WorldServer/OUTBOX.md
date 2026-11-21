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

WorldServer retains a bounded 256-entry in-memory compatibility map for legacy diagnostics, but this is no longer the authoritative contributor ledger. Effective damage from melee attacks, player-owned projectiles (including arrows and spells), and periodic burn ticks is admitted into the durable SQLite inbox and aggregated by authenticated session and character without the legacy 256-contributor cap. Death finalization reads this SQLite ledger and emits damage-ranked contribution events in chunks of at most 256 contributors per event, so a monster can have more than 256 contributors without truncating the durable snapshot. The center service now aggregates multiple chunk events by `(task_id, monster_instance_id)` in both publisher audit and player contribution history; it does not count each chunk as a separate monster. The in-memory map is retained only for compatibility diagnostics and is not the source for bounty/reward settlement.

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

The local outbox database now also creates `monster_damage_contributions`, keyed by runtime monster instance, authenticated session, and character. `DurableOutbox::record_monster_contribution` atomically upserts effective damage and hit counts with signed-64-bit saturation, preserves first/last-hit timestamps, and stores the caller's complete deduplicated objective-subscription JSON. Every write requires a stable `write_id`: an exact retry is a no-op, while reusing the ID with different data is rejected. The write-ID journal is removed together with the monster ledger during finalization. A finalization tombstone rejects late writes and prevents the same runtime monster from being finalized with a different event batch. `load_monster_contributions` returns a stable damage-ranked view and clears the caller's reusable error string before reading. Callers can therefore distinguish a successful empty ledger from a failed query by checking the error output rather than interpreting an empty vector alone.

`finalize_monster_contributions` inserts all death-time outbox events and deletes that monster's live ledger rows inside one `BEGIN IMMEDIATE` transaction. It clears a caller-reused error string before starting, so a successful first-time or idempotent retry cannot be mistaken for a previous failure. If validation, event-ID conflict, or outbox capacity fails, the transaction rolls back and the contribution rows remain available for retry. Repeating an identical finalization is idempotent because existing matching outbox rows are accepted.

**Integration boundary (historical groundwork, updated by the live integrations below):** SQLite writes are performed by the asynchronous contribution writer, never directly on the game thread. Direct melee and player-owned projectile hits now submit immutable records through the bounded writer before health is mutated. Online-owner periodic burn ticks and death-time drain/load/finalize are still pending. The existing 256-entry in-memory map remains the current death-snapshot source, so the SQLite ledger is not yet the authoritative settlement source. This ledger also does not restore active monsters after process restart; monster runtime state and health are not persisted. A later integration step must define stale-row expiry for runtime IDs whose monsters were not restored.


### Spawn-point identity versus contribution-instance identity

A monster's network `runtime_id` identifies its stable spawn point and is reused after respawn. It must **not** be used as the durable contribution ledger key: the ledger's finalization tombstone would otherwise reject every later life of that spawn. WorldServer now assigns a fresh `contribution_instance_id` when each monster life is created (including configured spawns and respawns). Contribution snapshots send this per-life ID as `monster_instance_id`; the stable `runtime_id` remains unchanged for targeting and replication.


## Bounded asynchronous monster contribution writer groundwork

A separate `MonsterContributionWriter` now provides the first worker-thread boundary for the SQLite contribution ledger:

- Combat-facing callers submit immutable records to a bounded FIFO (default capacity 32,768); submission fails explicitly when full or stopping.
- A single worker performs SQLite writes away from the game thread. It preserves the exact record and `write_id` across retries, with a 100 ms–2 s capped backoff.
- Per-monster pending counts allow a death path to wait for one life-instance queue to drain before reading/finalizing its ledger. The wait has a caller-supplied timeout.
- The in-memory queue is a bounded scheduling layer; the SQLite inbox is the durable source of truth. A successful submission commits the full write before the damage callback runs.
- The worker is FIFO and retains the exact write ID/payload while retrying. A poison record blocks later writes rather than silently skipping evidence; monitor `last_error()`.
- `stop()` is immediate and may leave rows in the durable inbox. They are not lost: the next writer startup reloads and replays them. `stop_after_drain()` is still preferred for orderly shutdown.

The WorldServer owns one writer alongside its `DurableOutbox`. It is constructed after the SQLite owner, reloads pending inbox rows before combat starts, and is stopped before the outbox owner is destroyed. Member declaration order also preserves safe resource lifetime.

The direct melee hit path is now the first live integration:

- It builds one immutable SQLite contribution record using the monster's per-life `contribution_instance_id`, authenticated session/character IDs, effective damage, one hit, wall-clock timestamps, and a deduplicated JSON array of matching cached monster-kill objective subscriptions.
- It calls `submit_before_damage`; only after the bounded writer accepts the record does the callback mutate monster health.
- If the writer is unavailable, stopping, or full, the hit is rejected and monster health is unchanged. The rejection is logged and the client receives a retry-later combat response.
- After admission, the existing in-memory 256-entry contribution map is still updated for the current death snapshot and bounty event compatibility.

**Historical partial-integration note:** this paragraph described the state before the live death-finalization integration below. The current lethal paths now drain and snapshot the SQLite ledger. The 256-entry in-memory compatibility map remains only for legacy diagnostics; SQLite is the contributor source for finalization.

The writer's lethal-path integration is complete for melee, projectile, and online/offline burn. Lethal contributions are atomically committed with death intent; nonlethal contributions use the durable inbox and replay path. The finalizer emits immutable contribution events in chunks of at most 256 contributors.

### Projectile impact admission

A player-owned projectile that hits a live monster now creates the same immutable per-life contribution record as a melee hit and calls `submit_before_damage` before changing health. Only an accepted queue submission applies the calculated health value. Slow, freeze, and burn-on-hit effects are applied only after admission succeeds, so a full/stopping writer cannot leave status effects without the corresponding damage. If admission fails, the server logs the rejection, sends the projectile owner a retry-later combat response, and removes the projectile so it cannot hit repeatedly on later ticks. After admission, the legacy in-memory contribution map is still updated for existing death/bounty compatibility.

Projectile contribution admission is durable before health changes. The remaining crash-consistency boundary is between the SQLite admission and the in-memory health mutation, not loss of an accepted inbox row.


### Pre-damage admission contract

The writer exposes `submit_before_damage(record, callback, error)` as the required ordering primitive. It first commits the immutable contribution into the SQLite inbox, then invokes a `noexcept` health-mutation callback. If the durable inbox is busy, invalid, or the bounded scheduling queue is full/stopping, the callback is not invoked and the hit is rejected. The callback is constrained to be non-throwing. All live nonlethal melee/projectile/burn paths use this contract; lethal paths use the stronger atomic contribution-plus-death-intent transaction.


The async writer test now persists two hits, closes/reopens the database before a worker starts, then verifies the new writer reconstructs and drains the queue. It also holds a SQLite write lock to verify backpressure, tests duplicate admission without double-counting, and simulates a crash after inbox admission but before aggregation.

### Periodic burn tick admission

When a burn tick is due and its owner is still online, WorldServer snapshots the periodic-effect timer before consuming the tick, builds a contribution record for the effective damage, and submits it through `submit_before_damage`. The SQLite inbox commit occurs before health mutation. If admission fails, the server restores the exact pre-consumption burn timer state, logs backpressure, notifies the owner, and retries the same tick on a later update.

After successful durable admission, the legacy in-memory contribution map is updated using captured session/character/objective attribution, even when the burn source has disconnected. If admission fails, the exact pre-tick effect state is restored and the tick is retried later. A defensive source-less legacy fallback persists a death intent before applying lethal damage.

This integration removes the online-owner burn tick's lost-tick failure mode under admission backpressure. Death finalization stops new hits, waits for the durable inbox to drain for that life, loads the SQLite ledger, and atomically finalizes its event batch.

### Bounded graceful shutdown for contribution writes

WorldServer shutdown calls `MonsterContributionWriter::stop_after_drain` after the combat loop stops admitting new hits and before the SQLite owner is destroyed. It waits up to five seconds for the durable inbox to be aggregated and acknowledged, then stops and joins the worker. A timeout logs the remaining queue size and last SQLite error; unfinished rows remain in SQLite and are replayed on the next startup. Joining may additionally wait for an already-running SQLite call to return.

This reduces shutdown backlog but does not replace per-monster death-time drain/finalization. A timeout is an operational warning; it no longer implies that admitted contribution rows are lost.


### Empty-objective monster finalization

A monster life may have durable damage contributors but no matching bounty objective subscriptions. `finalize_monster_contributions` accepts an empty event batch and atomically writes the per-life tombstone while clearing contribution rows. The live death finalizer now invokes this path when no bounty or reward events are required, so empty ledgers are still closed and late writes are rejected.


### Monster life lethal-closing latch

Each `MonsterRuntime` now has a per-life `contribution_closing` latch. The lethal melee, projectile, and attributed burn paths now persist the lethal contribution and pending-death intent in one SQLite transaction, then set this latch and apply zero health. The defensive legacy burn fallback persists its intent before applying lethal health. New melee/spell target selection, projectile impact, and subsequent burn ticks reject/skip a closing life. The latch is cleared only when a new contribution instance is assigned during respawn or explicit spawn reactivation.

This closes the same-tick duplicate-hit window. The live integration below now defers the ordinary `Dead` transition and respawn until SQLite finalization commits; the legacy 256-entry map is no longer used to build the authoritative death snapshot.

### Historical deferred monster-death finalization acceptance contract

These were the acceptance criteria before the live integration. They remain useful invariants for future changes; the current implementation uses the asynchronous writer/finalizer and durable intent described below. SQLite contention must not stall the authoritative simulation loop.

1. **Alive:** accepted damage is submitted to the bounded writer before health mutation.
2. **Closing:** the lethal hit and immutable pending-death context commit together in SQLite before health reaches zero and the per-life closing latch is set. All later damage/effect ticks for this life are rejected. Capture the authenticated killer identity and reward/drop intent as immutable data; do not retain a pointer or iterator into the live player map.
3. **Draining:** a world-update retry checks the per-instance writer count without blocking the simulation thread. While writes remain, the monster stays closing and cannot respawn.
4. **Snapshot:** after the writer reports drained, load the complete SQLite contribution ledger. A non-empty error is a hard failure; an empty vector with an empty error is a valid no-contributor snapshot.
5. **Prepared:** construct the complete bounty event batch from the SQLite records, not the legacy 256-entry in-memory compatibility map. Generate event IDs once and persist the exact prepared batch in SQLite before finalization. Every retry and restart must reuse the same IDs and byte-identical payloads.
6. **Finalizing:** call `finalize_monster_contributions(instance_id, batch, error)`. On failure, retain the ledger, pending batch, closing latch, and zero-health state; retry later with bounded backoff. Never substitute an empty batch after a load or parse failure.
7. **Committed:** only after atomic finalization succeeds may the server transition the monster to Dead and dispatch death rewards, drops, soul effects, and respawn timing. Those side effects need their own stable idempotency keys or must be included in the same durable transaction; a one-time in-memory boolean alone does not protect against process crashes between commit and dispatch.
8. **Respawn:** assign a fresh contribution instance ID and clear all per-life pending state. Never reuse a finalized ID.

The three lethal sources (melee, projectile, delayed burn) must enter this same state machine. Burn deaths may have no online killer; in that case preserve contributor snapshots but do not fabricate kill-progress or player rewards. Config reload must not discard a closing/finalizing life. The live integration below implements the above sequence for all three lethal sources. The remaining process-crash recovery boundary is documented separately.


### Preserve closing monster lives across spawn-config refresh

A spawn-config refresh must not replace the runtime definition or per-life contribution identity of a monster whose lethal transition has already been latched. The config merge now carries an existing `contribution_closing` runtime forward unchanged for that refresh instead of applying rare-spawn activation/deactivation or health changes to it. This protects the closing life from being revived or having its contribution identity rotated while its death lifecycle is pending. This config-reload guard preserves closing/finalizing lives while the live SQLite death finalizer completes. Closing monsters are retained even when their spawn point is removed from the refreshed configuration; ordinary non-closing removed spawn points continue to follow the existing merge policy.


### Non-blocking per-life writer pending count

The contribution writer now exposes `pending_count_for_monster(instance_id)`, a mutex-protected, non-blocking query for world-loop state machines. It includes both queued records and the record currently inside its SQLite commit because the per-monster counter is decremented only after a successful commit. The deferred death-finalization loop can use this to decide whether a life is ready for ledger loading without waiting on a condition variable or blocking the simulation thread. A zero count is only a writer-queue drain signal; callers must still check `load_monster_contributions` errors before treating the SQLite snapshot as authoritative.


### Asynchronous monster death finalizer worker

WorldServer now owns a dedicated `MonsterDeathFinalizer` worker next to the contribution writer. Its submission API accepts one per-life instance ID and an immutable event-builder callback. The worker performs the following sequence off the simulation thread:

1. Poll the contribution writer's non-blocking per-life pending count until it reaches zero.
2. Load the SQLite contribution ledger and treat any non-empty error as a failed snapshot, never as an empty ledger.
3. Invoke the event builder once and retain the exact resulting event batch in the task.
4. Retry `finalize_monster_contributions` with that same batch until the atomic outbox/tombstone/ledger transaction succeeds.
5. Publish a completion result for the game thread to consume; it does not mutate monster runtime state itself.

Duplicate submissions for the same life are rejected while a task is active. The worker is initialized after its SQLite dependencies and is stopped before the contribution writer/outbox during orderly shutdown. A focused test target exercises writer drain, authoritative ledger loading, event batch creation, finalization, and result delivery.

**Historical integration boundary:** when this worker was first added, lethal handlers had not yet submitted tasks. The live integration below now submits all three death sources and consumes completion results. The task queue remains process-local, but the pending intent and prepared event batch are now durable in SQLite; startup recovery reconstructs tasks from those records.


### Live SQLite-backed monster death settlement integration

The WorldServer lethal paths now submit all three death sources—direct melee, player-owned projectile impact, and periodic burn—through the asynchronous per-life finalizer. The lethal damage callback closes the life before any later attack can be admitted. The monster remains in a visible `death_pending` state with zero health while the writer drains and SQLite finalization retries; it is not switched to `Dead` and receives no respawn deadline until the finalizer reports the atomic transaction committed.

The finalizer event builder uses the SQLite ledger as its only contributor source. It validates every stored objective JSON document, derives the deduplicated task subscriptions from those records, and creates bounty kill/contribution events. Contribution snapshots are split into batches of at most 256 contributors to respect the center endpoint's per-event limit; each chunk has its own stable event ID and is included in the same local SQLite finalization transaction. The exact batch is retained by the finalizer across transaction retries.

For an eligible online killer, the same atomic batch also contains the character reward, underworld soul reward/absorption where applicable, and pre-rolled ground-drop creation events. Drop IDs and payloads are captured before submission. Once the finalizer confirms commit, the simulation thread exposes the persisted drops, changes the monster to `Dead`, sets its configured respawn delay, and wakes the durable outbox delivery worker. A burn death whose source is offline still finalizes all prior SQLite contributors but does not invent an online killer reward.

The combat response marks lethal hits as `settlement_pending`; reward amounts are reported separately after commit. World snapshots expose `death_pending` while the monster is closing but not yet committed.

**Remaining reliability boundary:** durable intent, prepared event batches, and accepted nonlethal contribution writes now survive restart. The remaining ambiguity is cross-domain consistency if the process crashes after a durable inbox commit but before the in-memory monster health callback; world health and SQLite admission are not yet one transaction. The center contribution endpoint stores each 1–256 contributor chunk as a distinct immutable event, while backend audit/history queries now aggregate those chunks into one monster-life snapshot.


### Durable pending-death recovery and committed respawn lifecycle

The WorldServer now persists each immutable death intent in the same SQLite database as the contribution ledger and durable outbox. The `pending_monster_deaths` row is keyed by the per-life contribution instance ID and records the spawn runtime ID plus a versioned JSON snapshot of world/monster identity, level, death position, killer session/character, killer bounty subscriptions, reward eligibility, and pre-rolled ground drops. The row is saved atomically with the lethal hit's contribution record before health is mutated. The lethal path uses a nonblocking SQLite mutex acquisition and a short 200 ms SQLite busy timeout; if SQLite is busy or the transaction fails, the hit is rejected without applying damage. A source-less legacy burn fallback persists its death intent before applying the lethal health change.

The finalizer worker now consults this row before building events. Once the event builder has produced a batch, the complete event array—including IDs, types, payload bytes, retry metadata, and timestamps—is stored in `prepared_events_json` before any outbox finalization attempt. After a restart, the worker reuses this exact batch and does not invoke the builder again. Thus a crash after batch persistence cannot reroll loot or generate a second set of event IDs. The finalization transaction atomically inserts/validates the outbox events, writes the per-life contribution tombstone, removes contribution/write-journal rows, and marks the pending-death row committed with a timestamp.

Committed death rows are intentionally retained after finalization. Startup recovery matches their runtime IDs against the loaded spawn configuration, restores the monster as Dead, and calculates the remaining respawn delay from the persisted commit timestamp. Only when the respawn is actually applied does the simulation acknowledge and delete the committed pending-death row, then assign a fresh contribution instance ID. This also covers a crash after the SQLite commit but before the game thread consumed the completion result, and a crash while the monster is waiting to respawn. Spawn-config refresh preserves both closing lives and committed-but-not-yet-respawned lives. If a pending row's runtime is not currently present in the spawn config, the row is retained and recovery retries after the next config refresh.

Schema upgrades add `prepared_events_json` and `committed_at_ms` to existing `pending_monster_deaths` tables when absent. Tests now cover immutable intent idempotency/conflict detection, prepared batch persistence across database reopen, finalizer replay without invoking the builder, committed-state retention, and respawn acknowledgement.

**Remaining crash boundary:** both lethal and nonlethal accepted contributions now have durable SQLite admission before health mutation. The remaining ambiguity is cross-domain consistency: a process crash after the inbox commit but before the in-memory damage callback can preserve a contribution for damage that was not reflected in the lost in-memory world state. Resolving this requires durable world-state/damage sequencing or replayable authoritative combat commands.


### Durable combat contribution admission and restart replay

Ordinary accepted combat hits no longer rely on the writer's in-memory FIFO as their only admission record. Before the damage callback is allowed to mutate health, `MonsterContributionWriter::submit` commits the immutable write ID and full contribution payload to `monster_damage_contribution_inbox`. The SQLite admission path uses a non-blocking process mutex acquisition and a 50 ms SQLite busy timeout; a busy/full/error result rejects the hit before health changes. Repeated admission with the same write ID and identical payload is idempotent while the inbox row is pending; conflicting payloads and reuse of an already-applied ID as a new hit are rejected. The writer also rejects duplicate IDs already present in its in-memory scheduling queue before invoking the damage callback.

The asynchronous writer reconstructs its pending queue from the durable inbox during construction. For each item it first calls the existing idempotent ledger writer, which atomically records the write journal row and aggregates damage into `monster_damage_contributions`. It then deletes the inbox row only after confirming the write journal contains that write ID. A crash after ledger aggregation but before inbox acknowledgement is safe: startup replays the same write ID, the ledger recognizes the exact duplicate without adding damage again, and the worker retries acknowledgement. A crash before aggregation leaves the inbox row available for replay. The death finalizer's per-instance pending count includes recovered inbox entries, so it cannot snapshot the ledger while earlier accepted writes are still awaiting aggregation.

Tests now exercise durable admission idempotency/conflict rejection, database close/reopen before worker startup, recovered queue processing, queue backpressure before health mutation, and crash replay without double-counting.

**Remaining boundary:** the simulation's authoritative monster health and the SQLite contribution inbox are not one transaction. A process crash after durable admission but before the in-memory damage callback can leave an admitted contribution for damage that was not reflected in the lost in-memory world state. Eliminating that ambiguity requires durable world-state/damage sequencing or replaying authoritative combat commands, which is a larger simulation recovery design. This change guarantees contribution write durability and idempotent ledger aggregation, but does not claim full world-state crash consistency.
