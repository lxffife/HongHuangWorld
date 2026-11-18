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

| State | Meaning | Authority |
| --- | --- | --- |
| authenticated | Presented access token maps to a valid, non-revoked Identity session | Identity |
| chat_online | At least one Chat connection lease is active | Chat |
| in_game | At least one active Game world session exists for the character | Game; Chat's view is an asynchronous projection |
| online | Product-level aggregate derived from Chat or Game connections, subject to valid authentication | Presence aggregation, not an Identity DB column |

A user can be chat-online without being in a world, and can be in a world while the Chat WebSocket is disconnected. A valid token alone must never be shown as online.

## Connection lifecycle

1. The client logs in through Identity and receives an access token.
2. Chat validates that token through the Identity introspection API before accepting a WebSocket connection. Chat does not read Identity's database.
3. Chat records a connection lease in the Chat database, keyed by a unique connection ID and associated with the Identity account ID.
4. Client WebSocket heartbeats refresh the lease. Clean disconnect deletes it; a crashed process leaves a lease that expires.
5. Multiple devices/connections are independent leases. The account remains chat-online while any unexpired lease exists.
6. Game independently creates and closes world sessions. Game events update Chat-owned projections asynchronously.

## Failure behavior

- Identity outage: Chat cannot authenticate new connections; existing sockets follow bounded token revalidation.
- Chat outage: Game simulation and Game world sessions continue.
- Game outage or NATS delay: Chat messaging and Chat presence continue, but projected Game state may be stale.
- NATS outage: Game Outbox retains events for later publication.
- Presence is ephemeral operational state, not permanent Identity login-session data.

## Current implementation

- Chat WebSocket handshakes authenticate through Identity HTTP introspection. Chat never reads Identity tables.
- Each WebSocket connection has an independent 90-second lease; the cleanup worker removes expired rows once per minute.
- GET /api/v1/chat/presence returns only the caller's Chat connection state.
- GET /api/v1/chat/presence/friends returns Chat presence for accepted friend characters only.
- GET /api/v1/chat/presence/summary returns the caller's current character's observed `online` aggregate, Chat connection count, projected active Game session count, and latest successfully processed Game-event receive time. The aggregate is `chat_online OR in_game` and is explicitly projection-derived.
- GET /api/v1/chat/presence/friends/summary returns the same observed aggregate and both component dimensions for accepted friend characters only.
- The summary includes game_projection_last_event_at as diagnostic metadata. It is the receive time of the latest successfully processed Game event, not a guarantee that every Game node is currently healthy. Clients should display Game presence as projection-derived and avoid treating delayed projection as authoritative real-time state.
- Chat's Game projection uses the Chat database only. It does not query Game or Identity databases.

The current summary API is a read model, not a new source of truth. The next stage can add cross-node presence transition events and push fanout without coupling Chat availability to Game simulation.
