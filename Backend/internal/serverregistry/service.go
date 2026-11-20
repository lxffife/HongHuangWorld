package serverregistry

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
	"time"
)

var (
	ErrInvalidHeartbeat = errors.New("invalid heartbeat")
	ErrInvalidNodeState = errors.New("invalid node administrative state")
	ErrNodeNotFound = errors.New("world server node not found")
	ErrNodeHasSessions = errors.New("world server node still has active or pending sessions")
)

type Heartbeat struct {
	NodeKey        string
	Host           string
	UDPPort        int
	Region         string
	Capacity       int
	CurrentPlayers int
	WorldID        string
	InstanceKey    string
	Status         string
}

type Result struct {
	ServerID   string `json:"server_id"`
	InstanceID string `json:"instance_id"`
}

type Service struct {
	db *sql.DB
}

func NewService(db *sql.DB) *Service {
	return &Service{db: db}
}

type Node struct {
	ID string `json:"id"`
	NodeKey string `json:"node_key"`
	Host string `json:"host"`
	UDPPort int `json:"udp_port"`
	Region string `json:"region"`
	Capacity int `json:"capacity"`
	ReportedPlayers int `json:"reported_players"`
	Status string `json:"status"`
	AdminState string `json:"admin_state"`
	LastHeartbeatAt *time.Time `json:"last_heartbeat_at"`
	ActiveSessions int `json:"active_sessions"`
	PendingSessions int `json:"pending_sessions"`
	WorldInstances int `json:"world_instances"`
	WorldNames string `json:"world_names"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

func (s *Service) ListNodes(ctx context.Context) ([]Node, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT sr.id::text, sr.node_key, sr.host, sr.udp_port, sr.region, sr.capacity, sr.current_players,
		       CASE WHEN sr.admin_state = 'disabled' THEN 'offline'
		            WHEN sr.admin_state = 'draining' THEN 'draining'
		            WHEN sr.last_heartbeat_at IS NULL OR sr.last_heartbeat_at < now() - interval '30 seconds' THEN 'offline'
		            ELSE sr.status END,
		       sr.admin_state, sr.last_heartbeat_at,
		       (SELECT COUNT(*) FROM world_sessions ws WHERE ws.server_id = sr.id AND ws.session_state = 'active')::int,
		       (SELECT COUNT(*) FROM world_sessions ws WHERE ws.server_id = sr.id AND ws.session_state IN ('connecting','saving'))::int,
		       (SELECT COUNT(*) FROM world_instances wi WHERE wi.server_id = sr.id)::int,
		       COALESCE((SELECT string_agg(DISTINCT wd.name, ', ' ORDER BY wd.name) FROM world_instances wi JOIN world_definitions wd ON wd.id = wi.world_id WHERE wi.server_id = sr.id), ''),
		       sr.created_at, sr.updated_at
		FROM server_registry sr ORDER BY sr.updated_at DESC, sr.node_key
	`)
	if err != nil { return nil, fmt.Errorf("list world server nodes: %w", err) }
	defer rows.Close()
	nodes := make([]Node, 0)
	for rows.Next() {
		var node Node
		var heartbeat sql.NullTime
		if err := rows.Scan(&node.ID, &node.NodeKey, &node.Host, &node.UDPPort, &node.Region, &node.Capacity, &node.ReportedPlayers, &node.Status, &node.AdminState, &heartbeat, &node.ActiveSessions, &node.PendingSessions, &node.WorldInstances, &node.WorldNames, &node.CreatedAt, &node.UpdatedAt); err != nil { return nil, fmt.Errorf("scan world server node: %w", err) }
		if heartbeat.Valid { value := heartbeat.Time; node.LastHeartbeatAt = &value }
		nodes = append(nodes, node)
	}
	if err := rows.Err(); err != nil { return nil, fmt.Errorf("iterate world server nodes: %w", err) }
	return nodes, nil
}

func (s *Service) SetAdminState(ctx context.Context, nodeKey, state string) (int64, error) {
	nodeKey = strings.TrimSpace(nodeKey)
	if nodeKey == "" || len(nodeKey) > 96 || (state != "normal" && state != "draining" && state != "disabled") { return 0, ErrInvalidNodeState }
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil { return 0, fmt.Errorf("begin world server node control: %w", err) }
	defer tx.Rollback()
	var serverID string
	if err := tx.QueryRowContext(ctx, `SELECT id::text FROM server_registry WHERE node_key = $1 FOR UPDATE`, nodeKey).Scan(&serverID); err != nil {
		if errors.Is(err, sql.ErrNoRows) { return 0, ErrNodeNotFound }
		return 0, fmt.Errorf("load world server node: %w", err)
	}
	// Disabling is only safe after the node has drained naturally. Never
	// rewrite live sessions to "saving": that is not a confirmed disconnect.
	if state == "disabled" {
		var remaining int64
		if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM world_sessions WHERE server_id = $1::uuid AND session_state IN ('connecting','active','saving')`, serverID).Scan(&remaining); err != nil {
			return 0, fmt.Errorf("count node sessions before disable: %w", err)
		}
		if remaining > 0 { return remaining, ErrNodeHasSessions }
	}
	if _, err := tx.ExecContext(ctx, `UPDATE server_registry SET admin_state = $2, updated_at = now() WHERE id = $1::uuid`, serverID, state); err != nil { return 0, fmt.Errorf("update world server node state: %w", err) }
	instanceStatus := "offline"
	if state == "draining" { instanceStatus = "draining" }
	if state == "normal" {
		if _, err := tx.ExecContext(ctx, `UPDATE world_instances wi SET status = CASE WHEN sr.status = 'ready' AND sr.last_heartbeat_at > now() - interval '30 seconds' THEN 'ready' ELSE 'offline' END, updated_at = now() FROM server_registry sr WHERE wi.server_id = sr.id AND sr.id = $1::uuid`, serverID); err != nil { return 0, fmt.Errorf("restore world server instances: %w", err) }
	} else {
		if _, err := tx.ExecContext(ctx, `UPDATE world_instances SET status = $2, updated_at = now() WHERE server_id = $1::uuid`, serverID, instanceStatus); err != nil { return 0, fmt.Errorf("update world server instances: %w", err) }
	}
	if err := tx.Commit(); err != nil { return 0, fmt.Errorf("commit world server node state: %w", err) }
	return 0, nil
}

func (s *Service) Heartbeat(ctx context.Context, input Heartbeat) (Result, error) {
	input.NodeKey = strings.TrimSpace(input.NodeKey)
	input.Host = strings.TrimSpace(input.Host)
	input.Region = strings.TrimSpace(input.Region)
	input.WorldID = strings.TrimSpace(input.WorldID)
	input.InstanceKey = strings.TrimSpace(input.InstanceKey)
	if input.NodeKey == "" || len(input.NodeKey) > 96 || input.Host == "" || len(input.Host) > 255 ||
		input.UDPPort < 1 || input.UDPPort > 65535 || input.Capacity < 1 || input.CurrentPlayers < 0 ||
		input.CurrentPlayers > input.Capacity || input.WorldID == "" || input.InstanceKey == "" || len(input.InstanceKey) > 64 {
		return Result{}, ErrInvalidHeartbeat
	}
	if input.Region == "" {
		input.Region = "local"
	}
	if input.Status != "ready" && input.Status != "draining" {
		return Result{}, ErrInvalidHeartbeat
	}

	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return Result{}, fmt.Errorf("begin server heartbeat: %w", err)
	}
	defer tx.Rollback()

	var worldEnabled bool
	if err := tx.QueryRowContext(ctx, `SELECT enabled FROM world_definitions WHERE id = $1`, input.WorldID).Scan(&worldEnabled); err != nil || !worldEnabled {
		return Result{}, ErrInvalidHeartbeat
	}

	var result Result
	err = tx.QueryRowContext(ctx,
		`INSERT INTO server_registry (node_key, host, udp_port, region, capacity, current_players, status, last_heartbeat_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, now())
		 ON CONFLICT (node_key) DO UPDATE SET host = EXCLUDED.host, udp_port = EXCLUDED.udp_port,
		 region = EXCLUDED.region, capacity = EXCLUDED.capacity, current_players = EXCLUDED.current_players,
		 status = CASE WHEN server_registry.admin_state = 'normal' THEN EXCLUDED.status ELSE server_registry.status END, last_heartbeat_at = now(), updated_at = now()
		 RETURNING id::text`,
		input.NodeKey, input.Host, input.UDPPort, input.Region, input.Capacity, input.CurrentPlayers, input.Status,
	).Scan(&result.ServerID)
	if err != nil {
		return Result{}, fmt.Errorf("upsert server registry: %w", err)
	}

	instanceIdentity := input.NodeKey + "\x00" + input.WorldID + "\x00" + input.InstanceKey
	instanceDigest := sha256.Sum256([]byte(instanceIdentity))
	instanceKey := "node/" + hex.EncodeToString(instanceDigest[:])
	err = tx.QueryRowContext(ctx,
		`INSERT INTO world_instances (world_id, instance_key, status, server_id)
		 VALUES ($1, $2, $3, $4)
		 ON CONFLICT (instance_key) DO UPDATE SET status = CASE WHEN (SELECT admin_state FROM server_registry WHERE id = EXCLUDED.server_id) = 'draining' THEN 'draining' WHEN (SELECT admin_state FROM server_registry WHERE id = EXCLUDED.server_id) = 'disabled' THEN 'offline' ELSE EXCLUDED.status END, server_id = EXCLUDED.server_id, updated_at = now()
		 WHERE world_instances.world_id = EXCLUDED.world_id
		 RETURNING id::text`,
		input.WorldID, instanceKey, input.Status, result.ServerID,
	).Scan(&result.InstanceID)
	if err != nil {
		return Result{}, fmt.Errorf("upsert world instance: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return Result{}, fmt.Errorf("commit server heartbeat: %w", err)
	}
	return result, nil
}
