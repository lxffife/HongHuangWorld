package serverregistry

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
)

var ErrInvalidHeartbeat = errors.New("invalid heartbeat")

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
		 status = EXCLUDED.status, last_heartbeat_at = now(), updated_at = now()
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
		 ON CONFLICT (instance_key) DO UPDATE SET status = EXCLUDED.status, server_id = EXCLUDED.server_id, updated_at = now()
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
