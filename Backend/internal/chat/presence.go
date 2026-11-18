package chat

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"time"
)

const defaultPresenceLease = 90 * time.Second

type PresenceStatus struct {
	ChatOnline bool      `json:"chat_online"`
	Connections int      `json:"connections"`
	CheckedAt  time.Time `json:"checked_at"`
}

func normalizePresenceLease(lease time.Duration) time.Duration {
	if lease < 30*time.Second || lease > 5*time.Minute {
		return defaultPresenceLease
	}
	return lease
}

// OpenPresenceLease registers one authenticated Chat WebSocket connection.
// Each device/socket has its own lease so one disconnect cannot mark the
// account offline while another connection remains active.
func (s *Service) OpenPresenceLease(ctx context.Context, connectionID, accountID, characterID, nodeID string, lease time.Duration) error {
	connectionID = strings.TrimSpace(connectionID)
	accountID = strings.TrimSpace(accountID)
	characterID = strings.TrimSpace(characterID)
	nodeID = strings.TrimSpace(nodeID)
	if !isUUID(connectionID) || !isUUID(accountID) || !isUUID(characterID) || nodeID == "" || len(nodeID) > 96 {
		return ErrInvalidInput
	}
	lease = normalizePresenceLease(lease)
	_, err := s.db.ExecContext(ctx, `
		INSERT INTO chat_presence_sessions(connection_id,account_id,character_id,node_id,connected_at,last_seen_at,expires_at)
		VALUES($1::uuid,$2::uuid,$3::uuid,$4,now(),now(),now()+make_interval(secs => $5::double precision))
		ON CONFLICT(connection_id) DO UPDATE SET
			account_id=EXCLUDED.account_id,
			character_id=EXCLUDED.character_id,
			node_id=EXCLUDED.node_id,
			connected_at=now(),
			last_seen_at=now(),
			expires_at=EXCLUDED.expires_at`,
		connectionID, accountID, characterID, nodeID, lease.Seconds())
	if err != nil {
		return fmt.Errorf("open chat presence lease: %w", err)
	}
	return nil
}

// RefreshPresenceLease extends a live lease. Expired leases are not revived;
// a connection that missed its lease deadline must reconnect and re-authenticate.
func (s *Service) RefreshPresenceLease(ctx context.Context, connectionID, characterID string, lease time.Duration) (bool, error) {
	lease = normalizePresenceLease(lease)
	result, err := s.db.ExecContext(ctx, `
		UPDATE chat_presence_sessions
		SET character_id=$2::uuid,last_seen_at=now(),
		    expires_at=now()+make_interval(secs => $3::double precision)
		WHERE connection_id=$1::uuid AND expires_at>now()`,
		connectionID, characterID, lease.Seconds())
	if err != nil {
		return false, fmt.Errorf("refresh chat presence lease: %w", err)
	}
	count, err := result.RowsAffected()
	if err != nil {
		return false, fmt.Errorf("read chat presence refresh result: %w", err)
	}
	return count == 1, nil
}

func (s *Service) ClosePresenceLease(ctx context.Context, connectionID string) error {
	if !isUUID(connectionID) {
		return ErrInvalidInput
	}
	if _, err := s.db.ExecContext(ctx, `DELETE FROM chat_presence_sessions WHERE connection_id=$1::uuid`, connectionID); err != nil {
		return fmt.Errorf("close chat presence lease: %w", err)
	}
	return nil
}

func (s *Service) GetChatPresence(ctx context.Context, accountID string) (PresenceStatus, error) {
	if !isUUID(accountID) {
		return PresenceStatus{}, ErrInvalidInput
	}
	var status PresenceStatus
	err := s.db.QueryRowContext(ctx, `
		SELECT count(*)::int,now()
		FROM chat_presence_sessions
		WHERE account_id=$1::uuid AND expires_at>now()`, accountID).
		Scan(&status.Connections, &status.CheckedAt)
	if err != nil {
		return PresenceStatus{}, fmt.Errorf("query chat presence: %w", err)
	}
	status.ChatOnline = status.Connections > 0
	return status, nil
}

// PruneExpiredPresenceLeases is safe to run on every Chat node. Expiry is the
// source of truth; this cleanup only bounds table growth.
func (s *Service) PruneExpiredPresenceLeases(ctx context.Context) (int64, error) {
	result, err := s.db.ExecContext(ctx, `DELETE FROM chat_presence_sessions WHERE expires_at<=now()`)
	if err != nil {
		return 0, fmt.Errorf("prune expired chat presence leases: %w", err)
	}
	count, err := result.RowsAffected()
	if err != nil {
		return 0, fmt.Errorf("read expired presence deletion count: %w", err)
	}
	return count, nil
}

var _ = sql.ErrNoRows
