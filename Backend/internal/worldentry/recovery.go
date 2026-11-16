package worldentry

import (
	"context"
	"database/sql"
	"fmt"
)

// RecoverOrphanedSessions closes sessions only when both the node heartbeat and
// the session snapshot lease have expired. A live node with a temporarily
// failing heartbeat is not enough to evict a player whose snapshots continue.
func (s *Service) RecoverOrphanedSessions(ctx context.Context) (int64, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return 0, fmt.Errorf("begin orphan session recovery: %w", err)
	}
	defer tx.Rollback()

	if _, err := tx.ExecContext(ctx,
		`UPDATE server_registry
		 SET status = 'offline', updated_at = now()
		 WHERE status <> 'offline'
		   AND last_heartbeat_at < now() - INTERVAL '45 seconds'`,
	); err != nil {
		return 0, fmt.Errorf("mark stale world servers offline: %w", err)
	}

	result, err := tx.ExecContext(ctx,
		`UPDATE world_sessions ws
		 SET session_state = 'closed', disconnected_at = now(), updated_at = now()
		 FROM server_registry sr
		 WHERE ws.server_id = sr.id
		   AND sr.status = 'offline'
		   AND sr.last_heartbeat_at < now() - INTERVAL '45 seconds'
		   AND ws.updated_at < now() - INTERVAL '45 seconds'
		   AND ws.session_state IN ('connecting', 'active', 'saving')`,
	)
	if err != nil {
		return 0, fmt.Errorf("close orphaned world sessions: %w", err)
	}
	closed, err := result.RowsAffected()
	if err != nil {
		return 0, fmt.Errorf("count recovered world sessions: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return 0, fmt.Errorf("commit orphan session recovery: %w", err)
	}
	return closed, nil
}

// Keep the database/sql import explicit in this file's API contract; the
// service owns the shared database connection pool.
var _ *sql.DB
