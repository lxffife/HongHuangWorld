# WorldServer Durable Outbox Foundation

> The SQLite storage module and tests are in place. Reward/drop worker integration is the next implementation step; until that wiring lands, existing in-memory workers remain active.

WorldServer reliable gameplay events use a node-local SQLite database. The database must live on persistent local storage, not /tmp or an ephemeral container layer.

## Storage

Set WORLD_SERVER_DATA_DIR to a writable persistent directory (planned default: ./data). The database is worldserver-outbox.sqlite3 in that directory. Keep this directory across upgrades and restarts, include it in node backups, and never share one database file between multiple WorldServer processes.

SQLite uses WAL journaling, synchronous=FULL, a busy timeout, and a bounded pending/in-flight event count. Event ID is the primary key; re-enqueueing the same ID is idempotent. Startup converts abandoned inflight records back to pending. Successful delivery marks an event delivered; retryable failures store attempts, next retry time, and last error; permanent failures move to dead_letter.

## Event contract

The outbox stores event type and the exact JSON payload sent to the center service. Never generate a new event ID when retrying. The center service must continue enforcing idempotency by server ID and event ID.

Planned event types:
- character_reward: experience and cultivation reward.
- ground_drop_create: persistent ground-drop creation.

Pickup settlement remains in the existing worker queue for now. Its center-service transaction and uniqueness constraints prevent duplicate consumption; durable pickup recovery will be added with the client-facing pending/confirmation recovery flow.

## Operations

- Monitor pending count and dead-letter records; dead-letter events require operator inspection.
- Do not delete the SQLite database to clear a queue.
- Back up with SQLite's online backup API or after clean shutdown. Copying only the main file while WAL is active may omit committed records.
- Local SQLite protects against process crashes and host restarts, not loss of the node storage device. Back up the data directory.
