# Identity Sessions and Online Presence

## Decision

Identity authentication and real-time online presence are separate concerns.

- Identity is the source of truth for accounts, credentials, access tokens, and login sessions.
- A valid Identity session means that a user is authenticated. It does not prove that the user currently has an active network connection.
- Chat owns chat-connection presence. A user is chat-online while at least one authenticated Chat WebSocket connection has a live presence lease.
- Game owns game-session presence. A character's active world session is authoritative for whether that character is currently in a Game world.
- Chat may consume Game session events into its own projection, but it must not query the Game database.
- No service other than Identity may read or write Identity tables directly.

## Presence meanings

Do not expose one ambiguous boolean as the only presence state. The application should distinguish:

| State | Meaning | Authority |
| --- | --- | --- |
| authenticated | The presented access token maps to a valid, non-revoked Identity session | Identity |
| chat_online | At least one Chat connection lease for the account is active | Chat |
| in_game | At least one active Game world session exists for the character | Game |
| online | A product-level aggregate derived from active Chat or Game connections, subject to a valid Identity session | Presence aggregation; not an Identity DB column |

A user can be chat-online without being in a world, and can be in a world while the Chat WebSocket is disconnected. A valid token alone must never be shown as online.

## Connection lifecycle

1. The client logs in through Identity and receives an access token.
2. Chat validates that token through the Identity introspection API before accepting a WebSocket connection. Chat does not read Identity's database.
3. Chat records a connection lease in the Chat database, keyed by a unique connection ID and associated with the Identity account ID. It records connected_at and last_seen_at.
4. The client sends periodic WebSocket heartbeats. Chat refreshes the lease only after a valid heartbeat.
5. On a clean disconnect, Chat marks or removes that connection lease. If the process crashes, the lease expires after its heartbeat deadline.
6. Multiple devices/connections are independent leases. The account remains chat-online while any unexpired lease exists.
7. The Game server independently creates and closes Game world sessions. Game events update Chat's local projection asynchronously.
8. An online-status query combines the relevant active connection facts; it does not infer presence from the Identity session table.

## Security and failure behavior

- Identity outage: Chat cannot authenticate new connections. Existing Chat sockets should have a bounded revalidation policy; revocation must not remain effective only for new HTTP requests.
- Chat outage: Game simulation and Game world sessions continue. Chat presence may be unavailable, but it must not affect movement or gameplay.
- Game outage: Chat messaging and Chat connection presence continue. in_game may be stale until the Game projection catches up or its lease expires.
- NATS outage: Game Outbox retains events for later publication. Chat remains usable; its Game projection may become stale and must expose its lag.
- A stale lease must expire automatically. Disconnect cleanup alone is insufficient because processes can crash.
- Presence is ephemeral operational state, not account history. It must not be stored as a permanent Identity login-session attribute.

## Current implementation

- Chat WebSocket handshakes authenticate through the Identity HTTP API. Chat never reads Identity tables.
- After a successful WebSocket upgrade, Chat creates one row in chat_presence_sessions for that connection.
- Client WebSocket ping frames and the Chat JSON ping message refresh the lease. The lease lasts 90 seconds; the socket read deadline is 75 seconds.
- A clean disconnect deletes that connection's lease. A process crash leaves a lease that becomes inactive automatically at expiry; a cleanup worker deletes expired rows once per minute.
- Multiple devices and Chat nodes use independent connection IDs. The account remains chat-online while at least one unexpired lease exists.
- GET /api/v1/chat/presence returns the authenticated caller's Chat-only presence and active connection count. It does not disclose other users' presence.
- While the socket is active, Chat revalidates the Identity token at least every 30 seconds when frames are received. The Identity client also has its short introspection cache; revocation propagation is therefore bounded by the revalidation interval, cache TTL, and network behavior.
- The Game-to-Chat consumer continues to project world-session events into Chat-owned tables. Game in-world status remains a separate state and is not included in chat_online.

The product-level aggregate online API (combining Chat connections and Game sessions), friend presence visibility, and richer presence fanout are intentionally separate follow-up work. Do not treat chat_online as proof that a player is in a Game world.

