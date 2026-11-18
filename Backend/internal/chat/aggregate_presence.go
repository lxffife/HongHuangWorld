package chat

import (
	"context"
	"fmt"
	"time"
)

// PresenceSummary keeps Chat connectivity and Game world-session state distinct.
// GameProjectionLastEventAt is diagnostic metadata: Game events are projected
// asynchronously, so consumers should not treat an old projection as a
// definitive real-time Game-offline signal.
type PresenceSummary struct {
	CharacterID              string     `json:"character_id"`
	Online                    bool       `json:"online"`
	ChatOnline                bool       `json:"chat_online"`
	ChatConnections           int        `json:"chat_connections"`
	InGame                    bool       `json:"in_game"`
	GameSessions              int        `json:"game_sessions"`
	GameProjectionLastEventAt *time.Time `json:"game_projection_last_event_at,omitempty"`
	CheckedAt                 time.Time  `json:"checked_at"`
	PresenceScope             string     `json:"presence_scope"`
}

type FriendPresenceSummary struct {
	CharacterID    string `json:"character_id"`
	Online         bool   `json:"online"`
	Name           string `json:"name"`
	ChatOnline     bool   `json:"chat_online"`
	ChatConnections int   `json:"chat_connections"`
	InGame         bool   `json:"in_game"`
	GameSessions   int    `json:"game_sessions"`
}

// GetPresenceSummary combines Chat-owned live connection leases with the
// asynchronously maintained Game world-session projection for the caller's
// current character. It never reads Identity or Game databases.
func (s *Service) GetPresenceSummary(ctx context.Context, accountID string) (PresenceSummary, error) {
	if !isUUID(accountID) {
		return PresenceSummary{}, ErrInvalidInput
	}
	var result PresenceSummary
	err := s.db.QueryRowContext(ctx, `
		SELECT
			COALESCE(a.current_character_id::text,''),
			count(DISTINCT p.connection_id)::int,
			count(DISTINCT ws.session_id) FILTER (WHERE ws.session_state='active')::int,
			(SELECT max(received_at) FROM game_projection_inbox WHERE processed_at IS NOT NULL),
			now()
		FROM chat_accounts a
		LEFT JOIN chat_presence_sessions p
			ON p.character_id=a.current_character_id AND p.expires_at>now()
		LEFT JOIN chat_world_sessions ws
			ON ws.character_id=a.current_character_id
		WHERE a.account_id=$1::uuid
		GROUP BY a.current_character_id
	`, accountID).Scan(
		&result.CharacterID,
		&result.ChatConnections,
		&result.GameSessions,
		&result.GameProjectionLastEventAt,
		&result.CheckedAt,
	)
	if err != nil {
		return PresenceSummary{}, fmt.Errorf("query combined presence summary: %w", err)
	}
	result.ChatOnline = result.ChatConnections > 0
	result.InGame = result.GameSessions > 0
	result.Online = result.ChatOnline || result.InGame
	result.PresenceScope = "chat+game_projection"
	return result, nil
}

// ListFriendPresenceSummary only returns characters in the caller's accepted
// friendship set. Both presence dimensions are read from Chat-owned data.
func (s *Service) ListFriendPresenceSummary(ctx context.Context, accountID string) ([]FriendPresenceSummary, error) {
	if !isUUID(accountID) {
		return nil, ErrInvalidInput
	}
	rows, err := s.db.QueryContext(ctx, `
		WITH current_character AS (
			SELECT current_character_id
			FROM chat_accounts
			WHERE account_id=$1::uuid AND current_character_id IS NOT NULL
		), friend_characters AS (
			SELECT f.addressee_character_id AS character_id
			FROM chat_friendships f
			JOIN current_character c ON c.current_character_id=f.requester_character_id
			UNION
			SELECT f.requester_character_id AS character_id
			FROM chat_friendships f
			JOIN current_character c ON c.current_character_id=f.addressee_character_id
		)
		SELECT
			c.character_id::text,
			c.name,
			count(DISTINCT p.connection_id)::int,
			count(DISTINCT ws.session_id) FILTER (WHERE ws.session_state='active')::int
		FROM friend_characters f
		JOIN chat_characters c ON c.character_id=f.character_id AND c.status='alive'
		LEFT JOIN chat_presence_sessions p
			ON p.character_id=c.character_id AND p.expires_at>now()
		LEFT JOIN chat_world_sessions ws
			ON ws.character_id=c.character_id
		GROUP BY c.character_id,c.name
		ORDER BY c.name,c.character_id
	`, accountID)
	if err != nil {
		return nil, fmt.Errorf("query friend combined presence: %w", err)
	}
	defer rows.Close()
	items := make([]FriendPresenceSummary, 0)
	for rows.Next() {
		var item FriendPresenceSummary
		if err := rows.Scan(&item.CharacterID, &item.Name, &item.ChatConnections, &item.GameSessions); err != nil {
			return nil, fmt.Errorf("scan friend combined presence: %w", err)
		}
		item.ChatOnline = item.ChatConnections > 0
		item.InGame = item.GameSessions > 0
		item.Online = item.ChatOnline || item.InGame
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate friend combined presence: %w", err)
	}
	return items, nil
}
