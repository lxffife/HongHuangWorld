# WorldServer Durable Outbox

WorldServer persists gameplay events to a node-local SQLite database **before** attempting delivery to the center service. Character rewards and ground-drop creation use this path. Pickup settlement still uses its existing worker and center-service transaction; durable pickup replay is not yet implemented.

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

Each event has a stable UUID/ID and exact serialized JSON payload. Re-enqueuing the same ID and identical payload is idempotent; reusing an ID with a different type or payload is rejected.

The worker claims due events from SQLite. Successful HTTP delivery marks the event `delivered`. Network errors and HTTP 5xx are persisted as retry state with exponential backoff (capped at five minutes). HTTP 4xx and malformed/unsupported events move to `dead_letter`. A process restart resets abandoned `inflight` records to `pending`; the same event ID is replayed, so the center service must keep enforcing idempotency.

The outbox retains delivered and dead-letter rows for diagnosis; they do not count against the pending/in-flight capacity. No automatic retention purge is performed yet.

## Reliability boundaries

- This protects events after their SQLite transaction commits, including process crashes and host restarts when the data directory survives.
- It does not protect against disk/device loss without backups.
- A failure to write the event (disk full, permissions, database error, or capacity reached) is logged; it cannot be described as durable acceptance.
- Pickup requests remain in the in-memory worker queue. Their center-service transaction prevents duplicate consumption for requests that reach the backend, but an unsubmitted pickup is not yet recovered by this outbox.
- Normal shutdown stops the outbox worker after its current delivery attempt. Pending and delayed-retry records remain on disk for the next start.
